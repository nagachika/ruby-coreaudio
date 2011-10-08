#include <stdio.h>
#include <unistd.h>

#include <Foundation/Foundation.h>
#include <CoreAudio/CoreAudio.h>

#include <ruby.h>

#include <AudioToolbox/AudioToolbox.h>

#include "coreaudio.h"


VALUE rb_cAudioFile;

static VALUE sym_read, sym_write, sym_format;
static VALUE sym_rate, sym_file_rate, sym_channel, sym_file_channel;
static VALUE sym_wav, sym_m4a;

static void
setASBD(AudioStreamBasicDescription *asbd,
        Float64 rate,
        UInt32 format,
        UInt32 flags,
        UInt32 channel,
        UInt32 bitsPerChannel,
        UInt32 framePerPacket)
{
    asbd->mSampleRate = rate;
    asbd->mFormatID = format;
    asbd->mFormatFlags = flags;
    asbd->mBitsPerChannel = bitsPerChannel;
    asbd->mChannelsPerFrame = channel;
    asbd->mFramesPerPacket = framePerPacket;
    asbd->mBytesPerFrame = bitsPerChannel/8*channel;
    asbd->mBytesPerPacket = bitsPerChannel/8*channel*framePerPacket;
}

typedef struct {
  AudioStreamBasicDescription file_desc;
  AudioStreamBasicDescription inner_desc;
  Boolean                     for_write;
  ExtAudioFileRef             file;
} ca_audio_file_t;

static void
ca_audio_file_free(void *ptr)
{
    ca_audio_file_t *data = ptr;

    if ( data->file ) {
      CFRelease(data->file);
      data->file = NULL;
    }
}

static size_t
ca_audio_file_memsize(const void *ptr)
{
    (void)ptr;
    return sizeof(ca_audio_file_t);
}

static const rb_data_type_t ca_audio_file_type = {
  "ca_audio_file",
  {NULL, ca_audio_file_free, ca_audio_file_memsize}
};

static VALUE
ca_audio_file_alloc(VALUE klass)
{
    VALUE obj;
    ca_audio_file_t *ptr;

    obj = TypedData_Make_Struct(klass, ca_audio_file_t, &ca_audio_file_type, ptr);

    return obj;
}

/*
 * call-seq:
 *   AudioFile.new(filepath, mode, opt)
 *
 * open audio file at +filepath+. +mode+ should be :read or :write
 * corresponding to file mode argument of Kernel#open.
 * +opt+ must contain :format key.
 *
 * 'client data' means audio data pass to AudioFile#write or from
 * AudioFile#read method.
 *
 * :format :: audio file format. currently audio file format and 
 *            codec type is hardcoded. (:wav, :m4a)
 * :rate :: sample rate of data pass from AudioFile#read or to AudioFile#write
 *          If not specified, :file_rate value is used. (Float)
 * :channel :: number of channels 
 * :file_rate :: file data sample rate. only work when open for output. (Float)
 * :file_channel :: file data number of channels. only work when open for
 *                  output.
 */
static VALUE
ca_audio_file_initialize(int argc, VALUE *argv, VALUE self)
{
    ca_audio_file_t *data;
    VALUE path, mode, opt, format;
    Float64 rate, file_rate;
    UInt32 channel, file_channel;
    CFURLRef outUrl = NULL;
    AudioFileTypeID filetype;
    UInt32 flags = kAudioFileFlags_EraseFile;
    OSStatus err = noErr;

    TypedData_Get_Struct(self, ca_audio_file_t, &ca_audio_file_type, data);

    rb_scan_args(argc, argv, "11:", &path, &mode, &opt);

    /* check mode */
    if (NIL_P(mode) || mode == sym_read)
      data->for_write = FALSE;
    else if (mode == sym_write)
        data->for_write = TRUE;
    else
      rb_raise(rb_eArgError, "coreaudio: mode should be :read or :write");

    /* parse options */
    if (NIL_P(rb_hash_aref(opt, sym_rate))) {
      rate = 44100.0;
    } else {
      rate = NUM2DBL(rb_hash_aref(opt, sym_rate));
    }
    if (NIL_P(rb_hash_aref(opt, sym_file_rate))) {
      file_rate = rate;
    } else {
      file_rate = NUM2DBL(rb_hash_aref(opt, sym_file_rate));
    }
    if (NIL_P(rb_hash_aref(opt, sym_channel))) {
      channel = 2;
    } else {
      channel = NUM2UINT(rb_hash_aref(opt, sym_channel));
    }
    if (NIL_P(rb_hash_aref(opt, sym_file_channel))) {
      file_channel = channel;
    } else {
      file_channel = NUM2UINT(rb_hash_aref(opt, sym_file_channel));
    }

    format = rb_hash_aref(opt, sym_format);
    if (NIL_P(format))
      rb_raise(rb_eArgError, "coreaudio: :format option must be specified");

    if (format == sym_wav) {
      filetype = kAudioFileWAVEType;
      setASBD(&data->file_desc, file_rate, kAudioFormatLinearPCM,
              kLinearPCMFormatFlagIsSignedInteger |
              kAudioFormatFlagIsPacked,
              file_channel, 16, 1);
    } else if (format == sym_m4a) {
      filetype = kAudioFileM4AType;
      setASBD(&data->file_desc, file_rate, kAudioFormatMPEG4AAC,
              0, file_channel, 0, 0);
    } else {
      volatile VALUE str = rb_inspect(format);
      RB_GC_GUARD(str);
      rb_raise(rb_eArgError, "coreaudio: unsupported format (%s)",
               RSTRING_PTR(str));
    }

    /* create URL represent the target filepath */
    outUrl = CFURLCreateFromFileSystemRepresentation(
                NULL, StringValueCStr(path), (CFIndex)RSTRING_LEN(path), FALSE);

    /* open ExtAudioFile */
    err = ExtAudioFileCreateWithURL(outUrl, filetype, &data->file_desc,
                                    NULL, flags, &data->file);
    CFRelease(outUrl);
    outUrl = NULL;
    if (err != noErr) {
      rb_raise(rb_eArgError,
               "coreaudio: file to open ExtAudioFile: %d", (int)err);
    }

    setASBD(&data->inner_desc, rate, kAudioFormatLinearPCM,
            kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            channel, 16, 1);

    err = ExtAudioFileSetProperty(
            data->file, kExtAudioFileProperty_ClientDataFormat,
            sizeof(data->inner_desc), &data->inner_desc);
    if (err != noErr) {
      ExtAudioFileDispose(data->file);
      data->file = NULL;
      rb_raise(rb_eArgError, "coreaudio: fail to set client data format: %d",
               (int)err);
    }

    return self;
}

static VALUE
ca_audio_file_close(VALUE self)
{
    ca_audio_file_t *data;

    TypedData_Get_Struct(self, ca_audio_file_t, &ca_audio_file_type, data);
    if (data->file) {
      ExtAudioFileDispose(data->file);
      data->file = NULL;
    }

    return self;
}

static VALUE
ca_audio_file_write(VALUE self, VALUE data)
{
    ca_audio_file_t *file;
    short *buf;
    AudioBufferList buf_list;
    UInt32 frames;
    size_t alloc_size;
    OSStatus err = noErr;
    int i;

    if (!RB_TYPE_P(data, T_ARRAY))
      rb_raise(rb_eArgError, "coreaudio: audio buffer must be an array");

    TypedData_Get_Struct(self, ca_audio_file_t, &ca_audio_file_type, file);

    frames = RARRAY_LENINT(data) / file->inner_desc.mChannelsPerFrame;
    alloc_size = (file->inner_desc.mBitsPerChannel/8) * RARRAY_LEN(data);

    /* prepare interleaved audio buffer */
    buf_list.mNumberBuffers = 1;
    buf_list.mBuffers[0].mNumberChannels = file->inner_desc.mChannelsPerFrame;
    buf_list.mBuffers[0].mDataByteSize = (UInt32)alloc_size;
    buf_list.mBuffers[0].mData = xmalloc(alloc_size);
    buf = buf_list.mBuffers[0].mData;

    for (i = 0; i < RARRAY_LEN(data); i++) {
      buf[i] = (short)NUM2INT(RARRAY_PTR(data)[i]);
    }

    err = ExtAudioFileWrite(file->file, frames, &buf_list);

    xfree(buf);

    if (err != noErr) {
      rb_raise(rb_eRuntimeError,
               "coreaudio: ExtAudioFileWrite() fails: %d", (int)err);
    }

    return self;
}

void
Init_coreaudio_audiofile(void)
{
    sym_read = ID2SYM(rb_intern("read"));
    sym_write = ID2SYM(rb_intern("write"));
    sym_format = ID2SYM(rb_intern("format"));
    sym_rate = ID2SYM(rb_intern("rate"));
    sym_file_rate = ID2SYM(rb_intern("file_rate"));
    sym_channel = ID2SYM(rb_intern("channel"));
    sym_file_channel = ID2SYM(rb_intern("file_channel"));
    sym_wav = ID2SYM(rb_intern("wav"));
    sym_m4a = ID2SYM(rb_intern("m4a"));

    rb_cAudioFile = rb_define_class_under(rb_mCoreAudio, "AudioFile",
                                          rb_cObject);
    rb_global_variable(&rb_cAudioFile);

    rb_define_alloc_func(rb_cAudioFile, ca_audio_file_alloc);
    rb_define_method(rb_cAudioFile, "initialize", ca_audio_file_initialize, -1);
    rb_define_method(rb_cAudioFile, "close", ca_audio_file_close, 0);
    rb_define_method(rb_cAudioFile, "write", ca_audio_file_write, 1);
}
