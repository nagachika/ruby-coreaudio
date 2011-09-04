#include <stdio.h>
#include <unistd.h>

#include <Foundation/Foundation.h>
#include <CoreAudio/CoreAudio.h>

#include <ruby.h>

static VALUE rb_mCoreAudio;
static VALUE rb_cAudioDevice;
static VALUE rb_cAudioStream;
static VALUE rb_cOutLoop;
static ID sym_iv_devid;
static ID sym_iv_name;
static ID sym_iv_available_sample_rate;
static ID sym_iv_nominal_rate;
static ID sym_iv_input_stream;
static ID sym_iv_output_stream;
static ID sym_iv_channels;
static ID sym_iv_buffer_frame_size;

/* utility macro */
#define PropertyAddress { \
  .mScope = kAudioObjectPropertyScopeGlobal,    \
  .mElement = kAudioObjectPropertyElementMaster \
}

static VALUE
ca_get_stream_channel_num(AudioDeviceID devID,
                          AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress address = PropertyAddress;
    UInt32 size;
    AudioChannelLayout *layout;
    OSStatus status;
    UInt32 ch_num;

    address.mSelector = kAudioDevicePropertyPreferredChannelLayout;
    address.mScope = scope;
    if (!AudioObjectHasProperty(devID, &address))
      return INT2NUM(0);

    status = AudioObjectGetPropertyDataSize(devID, &address, 0, NULL, &size);

    if (status != noErr) {
      rb_raise(rb_eArgError,
               "coreaudio: get preferred channel layout size failed: %d", status);
    }

    layout = alloca(size);

    status = AudioObjectGetPropertyData(devID, &address, 0, NULL, &size, layout);
    if (status != noErr) {
      rb_raise(rb_eArgError,
               "coreaudio: get preferred channel layout failed: %d", status);
    }

    if (layout->mChannelLayoutTag == kAudioChannelLayoutTag_UseChannelDescriptions) {
      ch_num = layout->mNumberChannelDescriptions;
    } else if (layout->mChannelLayoutTag == kAudioChannelLayoutTag_UseChannelBitmap) {
      UInt32 i;
      ch_num = 0;
      for ( i = 0; i < sizeof(layout->mChannelBitmap)*8; i++ ) {
        if ( (layout->mChannelBitmap >> i) & 0x01 )
          ch_num++;
      }
    } else {
      ch_num = AudioChannelLayoutTag_GetNumberOfChannels(layout->mChannelLayoutTag);
    }
    return UINT2NUM(ch_num);
}

static VALUE
ca_get_stream_buffer_frame(AudioDeviceID devID, AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress address = PropertyAddress;
    UInt32 size, framesize;
    OSStatus status;

    address.mSelector = kAudioDevicePropertyBufferFrameSize;
    address.mScope = scope;

    if (!AudioObjectHasProperty(devID, &address))
      return INT2NUM(0);

    size = sizeof(framesize);
    status = AudioObjectGetPropertyData(devID, &address, 0, NULL, &size, &framesize);
    if (status != noErr) {
      rb_raise(rb_eArgError,
               "coreaudio: get buffer frame size failed: %d", status);
    }
    return UINT2NUM(framesize);
}

static VALUE
ca_stream_initialize(VALUE self, VALUE devid_val, VALUE is_input)
{
    AudioDeviceID devID = (AudioDeviceID)NUM2UINT(devid_val);
    AudioObjectPropertyScope scope;

    if (RTEST(is_input))
      scope = kAudioDevicePropertyScopeInput;
    else
      scope = kAudioDevicePropertyScopeOutput;
    rb_ivar_set(self, sym_iv_channels, ca_get_stream_channel_num(devID, scope));
    rb_ivar_set(self, sym_iv_buffer_frame_size, ca_get_stream_buffer_frame(devID, scope));

    return self;
}

static VALUE
ca_stream_new(VALUE devid, VALUE is_input)
{
    VALUE stream;
    stream = rb_obj_alloc(rb_cAudioStream);
    ca_stream_initialize(stream, devid, is_input);
    return stream;
}

static VALUE
ca_get_device_name(AudioDeviceID devID)
{
    AudioObjectPropertyAddress address = PropertyAddress;
    UInt32 size;
    OSStatus status;
    CFStringRef deviceName = NULL;
    VALUE str;

    address.mSelector = kAudioObjectPropertyName;
    size = sizeof(deviceName);

    status = AudioObjectGetPropertyData(devID, &address, 0, NULL, &size, &deviceName);
    if ( status != noErr ) {
      rb_raise(rb_eArgError, "coreaudio: get device name failed: %d", status);
    }
    str = rb_str_new2(CFStringGetCStringPtr(deviceName, kCFStringEncodingASCII));
    CFRelease(deviceName);

    return str;
}

static VALUE
ca_get_device_available_sample_rate(AudioDeviceID devID)
{
    AudioObjectPropertyAddress address = PropertyAddress;
    UInt32 size;
    UInt32 n_rates;
    AudioValueRange *sample_rates;
    OSStatus status;
    VALUE ary;
    UInt32 i;

    address.mSelector = kAudioDevicePropertyAvailableNominalSampleRates;
    status = AudioObjectGetPropertyDataSize(devID, &address, 0, NULL, &size);

    if (status != noErr) {
      rb_raise(rb_eArgError,
               "coreaudio: get available sample rates size failed: %d", status);
    }

    n_rates = size / (UInt32)sizeof(AudioValueRange);
    sample_rates = ALLOCA_N(AudioValueRange, n_rates);

    status = AudioObjectGetPropertyData(devID, &address, 0, NULL, &size, sample_rates);
    if (status != noErr) {
      rb_raise(rb_eArgError,
               "coreaudio: get available sample rates failed: %d", status);
    }

    ary = rb_ary_new();
    for ( i = 0; i < n_rates; i++ ) {
      rb_ary_push(ary,
                  rb_ary_new3(2,
                              DBL2NUM((double)sample_rates[i].mMinimum),
                              DBL2NUM((double)sample_rates[i].mMaximum)));
    }

    return ary;
}

static VALUE
ca_get_device_nominal_sample_rate(AudioDeviceID devID)
{
    AudioObjectPropertyAddress address = PropertyAddress;
    UInt32 size;
    Float64 rate;
    OSStatus status;

    address.mSelector = kAudioDevicePropertyNominalSampleRate;
    status = AudioObjectGetPropertyDataSize(devID, &address, 0, NULL, &size);

    if (status != noErr) {
      rb_raise(rb_eArgError,
               "coreaudio: get nominal sample rates size failed: %d", status);
    }

    status = AudioObjectGetPropertyData(devID, &address, 0, NULL, &size, &rate);
    if (status != noErr) {
      rb_raise(rb_eArgError,
               "coreaudio: get nominal sample rates failed: %d", status);
    }
    return DBL2NUM((double)rate);
}

static VALUE
ca_get_device_actual_sample_rate(VALUE self)
{
    AudioDeviceID devID = NUM2UINT(rb_ivar_get(self, sym_iv_devid));
    AudioObjectPropertyAddress address = PropertyAddress;
    UInt32 size;
    Float64 rate;
    OSStatus status;

    address.mSelector = kAudioDevicePropertyActualSampleRate;
    status = AudioObjectGetPropertyDataSize(devID, &address, 0, NULL, &size);

    size = sizeof(rate);
    status = AudioObjectGetPropertyData(devID, &address, 0, NULL, &size, &rate);
    if (status != noErr) {
      rb_raise(rb_eArgError,
               "coreaudio: get actual sample rates failed: %d", status);
    }
    return DBL2NUM((double)rate);
}

static VALUE
ca_device_initialize(VALUE self, VALUE devIdVal)
{
    AudioDeviceID devID = (AudioDeviceID)NUM2LONG(devIdVal);
    VALUE device_name;
    VALUE available_sample_rate;
    VALUE nominal_rate;
    VALUE input_stream, output_stream;

    device_name = ca_get_device_name(devID);
    available_sample_rate = ca_get_device_available_sample_rate(devID);
    rb_obj_freeze(available_sample_rate);
    nominal_rate = ca_get_device_nominal_sample_rate(devID);
    input_stream = ca_stream_new(devIdVal, Qtrue);
    output_stream = ca_stream_new(devIdVal, Qfalse);

    rb_ivar_set(self, sym_iv_devid, devIdVal);
    rb_ivar_set(self, sym_iv_name, device_name);
    rb_ivar_set(self, sym_iv_available_sample_rate, available_sample_rate);
    rb_ivar_set(self, sym_iv_nominal_rate, nominal_rate);
    rb_ivar_set(self, sym_iv_input_stream, input_stream);
    rb_ivar_set(self, sym_iv_output_stream, output_stream);

    return self;
}

static VALUE
ca_device_new(AudioDeviceID devid)
{
    VALUE devIdVal = UINT2NUM(devid);
    VALUE device;

    device = rb_obj_alloc(rb_cAudioDevice);
    ca_device_initialize(device, devIdVal);

    return device;
}

static VALUE
ca_devices(VALUE mod)
{
    AudioObjectPropertyAddress address = PropertyAddress;
    AudioDeviceID *devIDs = NULL;
    UInt32 size = 0, devnum = 0;
    OSStatus status = noErr;
    VALUE ary;
    UInt32 i;

    address.mSelector = kAudioHardwarePropertyDevices;

    status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                            &address, 0, NULL, &size);
    if (status != noErr)
      rb_raise(rb_eRuntimeError, "coreaudio: get devices size failed: %d", status);

    devnum = size / (UInt32)sizeof(AudioDeviceID);
    devIDs = ALLOCA_N(AudioDeviceID, devnum);

    status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                        &address, 0, NULL, &size, devIDs);
    if (status != noErr)
      rb_raise(rb_eRuntimeError, "coreaudio: get devices failed: %d", status);

    ary = rb_ary_new();
    for (i = 0; i < devnum; i++) {
      rb_ary_push(ary, ca_device_new(devIDs[i]));
    }
    return ary;
}

static VALUE
ca_default_input_device(VALUE mod)
{
    AudioDeviceID devID;
    AudioObjectPropertyAddress address = PropertyAddress;
    UInt32 size;
    OSStatus status;

    address.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    size = sizeof(devID);

    status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                        &address, 0, NULL, &size, &devID);

    if (status != noErr)
      rb_raise(rb_eArgError, "coreaudio: get default input device failed: %d", status);

    return ca_device_new(devID);
}

static VALUE
ca_default_output_device(VALUE mod)
{
    AudioDeviceID devID;
    AudioObjectPropertyAddress address = PropertyAddress;
    UInt32 size;
    OSStatus status;

    address.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
    size = sizeof(devID);

    status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                        &address, 0, NULL, &size, &devID);

    if (status != noErr)
      rb_raise(rb_eArgError, "coreaudio: get default output device failed: %d", status);

    return ca_device_new(devID);
}

typedef struct {
  AudioDeviceID       devID;
  AudioDeviceIOProcID procID;
  UInt32              frame;
  UInt32              channel;
  float               *buf;
} ca_out_loop_data;

static void
ca_out_loop_data_free(void *ptr)
{
    if (ptr) {
      ca_out_loop_data *data = ptr;
      if (data->procID)
        AudioDeviceDestroyIOProcID(data->devID, data->procID);
      if (data->buf)
        free(data->buf);
      free(ptr);
    }
}

static size_t
ca_out_loop_data_memsize(const void *ptr)
{
    const ca_out_loop_data *data = ptr;
    return sizeof(ca_out_loop_data) + data->frame * sizeof(float);
}

static const rb_data_type_t ca_out_loop_data_type = {
  "ca_out_loop_data",
  {NULL, ca_out_loop_data_free, ca_out_loop_data_memsize},
};

static OSStatus
ca_out_loop_proc(
        AudioDeviceID           inDevice,
        const AudioTimeStamp*   inNow,
        const AudioBufferList*  inInputData,
        const AudioTimeStamp*   inInputTime,
        AudioBufferList*        outOutputData,
        const AudioTimeStamp*   inOutputTime,
        void*                   inClientData)
{
    NSUInteger i;
    UInt32 buffers = outOutputData->mNumberBuffers;
    ca_out_loop_data *loop_data = inClientData;

    for (i = 0; i < buffers; i++) {
      float *ptr = outOutputData->mBuffers[i].mData;
      UInt32 size = outOutputData->mBuffers[i].mDataByteSize / (UInt32)sizeof(float) / loop_data->channel;
      UInt32 offset = (UInt32)inOutputTime->mSampleTime % loop_data->frame;
      UInt32 copied = 0;

      if (outOutputData->mBuffers[i].mNumberChannels != loop_data->channel) {
        memset(ptr, 0, size * sizeof(float));
        continue;
      }

      while ( copied < size ) {
        UInt32 len = loop_data->frame - offset;
        if ( len > size - copied )
          len = size - copied;
        memcpy(ptr + copied*loop_data->channel, loop_data->buf + (offset * loop_data->channel), sizeof(float)*len*loop_data->channel);
        offset = (offset + len) % loop_data->frame;
        copied += len;
      }
    }

    return 0;
}

static VALUE
ca_out_loop_data_alloc(VALUE klass)
{
    VALUE obj;
    ca_out_loop_data *ptr;

    obj = TypedData_Make_Struct(klass, ca_out_loop_data, &ca_out_loop_data_type, ptr);
    return obj;
}

static VALUE
ca_out_loop_data_initialize(VALUE self, VALUE devID, VALUE frame, VALUE channel)
{
    ca_out_loop_data *data;
    OSStatus status;

    TypedData_Get_Struct(self, ca_out_loop_data, &ca_out_loop_data_type, data);
    data->devID = NUM2UINT(devID);
    status = AudioDeviceCreateIOProcID(data->devID, ca_out_loop_proc, data, &data->procID);
    if ( status != noErr )
    {
      rb_raise(rb_eRuntimeError, "coreaudio: create proc ID fail: %d", status);
    }
    data->frame = NUM2UINT(frame);
    data->channel = NUM2UINT(channel);
    data->buf = malloc(sizeof(float)*data->frame*data->channel);
    if (data->buf == NULL)
      rb_raise(rb_eNoMemError, "coreaudio: fail to alloc out loop data buffer");
    return self;
}

static VALUE
ca_device_create_out_loop_proc(VALUE self, VALUE frame)
{
    VALUE proc;
    VALUE out_stream = rb_ivar_get(self, sym_iv_output_stream);

    proc = ca_out_loop_data_alloc(rb_cOutLoop);
    ca_out_loop_data_initialize(proc, rb_ivar_get(self, sym_iv_devid), frame,
                                rb_ivar_get(out_stream, sym_iv_channels));
    return proc;
}

static VALUE
ca_out_loop_data_start(VALUE self)
{
    ca_out_loop_data *data;
    OSStatus status;

    TypedData_Get_Struct(self, ca_out_loop_data, &ca_out_loop_data_type, data);

    status = AudioDeviceStart(data->devID, data->procID);
    if ( status != noErr )
    {
      rb_raise(rb_eRuntimeError, "coreaudio: audio device start fail: %d", status);
    }
    return self;
}

static VALUE
ca_out_loop_data_stop(VALUE self)
{
    ca_out_loop_data *data;
    OSStatus status;

    TypedData_Get_Struct(self, ca_out_loop_data, &ca_out_loop_data_type, data);

    status = AudioDeviceStop(data->devID, data->procID);
    if ( status != noErr )
    {
      rb_raise(rb_eRuntimeError, "coreaudio: audio device stop fail: %d", status);
    }
    return self;
}

static VALUE
ca_out_loop_data_assign(VALUE self, VALUE index, VALUE val)
{
    ca_out_loop_data *data;

    TypedData_Get_Struct(self, ca_out_loop_data, &ca_out_loop_data_type, data);

    data->buf[NUM2UINT(index)] = (float)NUM2DBL(val);
}

#if 0
static VALUE
ca_test_callback(VALUE self)
{
    AudioDeviceID devID;
    AudioDeviceIOProcID procID;
    OSStatus status;
    ca_out_loop_data data;

    devID = NUM2UINT(rb_ivar_get(self, sym_iv_devid));

    status = AudioDeviceCreateIOProcID(devID, ca_io_proc, NULL, &procID);
    if ( status != noErr )
    {
      rb_raise(rb_eRuntimeError, "coreaudio: create proc ID fail: %d", status);
    }

    status = AudioDeviceStart(devID, procID);
    if ( status != noErr )
    {
      rb_raise(rb_eRuntimeError, "coreaudio: audio device start fail: %d", status);
    }

    sleep(5);

    status = AudioDeviceStop(devID, procID);
    if ( status != noErr )
    {
      rb_raise(rb_eRuntimeError, "coreaudio: audio device stop fail: %d", status);
    }

    status = AudioDeviceDestroyIOProcID(devID, procID);
    if ( status != noErr )
    {
      rb_raise(rb_eRuntimeError, "coreaudio: destroy IOProc fail: %d", status);
    }

    return self;
}
#endif

void
Init_coreaudio(void)
{
    sym_iv_devid = rb_intern("@devid");
    sym_iv_name = rb_intern("@name");
    sym_iv_available_sample_rate = rb_intern("@available_sample_rate");
    sym_iv_nominal_rate = rb_intern("@nominal_rate");
    sym_iv_input_stream = rb_intern("@input_stream");
    sym_iv_output_stream = rb_intern("@output_stream");
    sym_iv_channels = rb_intern("@channels");
    sym_iv_buffer_frame_size = rb_intern("@buffer_frame_size");

    rb_mCoreAudio = rb_define_module("CoreAudio");
    rb_cAudioDevice = rb_define_class_under(rb_mCoreAudio, "AudioDevice", rb_cObject);
    rb_cAudioStream = rb_define_class_under(rb_mCoreAudio, "AudioStream", rb_cObject);
    rb_cOutLoop = rb_define_class_under(rb_mCoreAudio, "OutLoop", rb_cObject);

    rb_define_method(rb_cAudioDevice, "initialize", ca_device_initialize, 1);
    rb_define_method(rb_cAudioDevice, "actual_rate", ca_get_device_actual_sample_rate, 0);
    rb_define_method(rb_cAudioDevice, "out_loop", ca_device_create_out_loop_proc, 1);
    rb_define_attr(rb_cAudioDevice, "devid", 1, 0);
    rb_define_attr(rb_cAudioDevice, "name", 1, 0);
    rb_define_attr(rb_cAudioDevice, "available_sample_rate", 1, 0);
    rb_define_attr(rb_cAudioDevice, "nominal_rate", 1, 0);
    rb_define_attr(rb_cAudioDevice, "input_stream", 1, 0);
    rb_define_attr(rb_cAudioDevice, "output_stream", 1, 0);

    rb_define_method(rb_cAudioStream, "initialize", ca_stream_initialize, 2);

    rb_define_singleton_method(rb_mCoreAudio, "devices", ca_devices, 0);
    rb_define_singleton_method(rb_mCoreAudio, "default_input_device", ca_default_input_device, 0);
    rb_define_singleton_method(rb_mCoreAudio, "default_output_device", ca_default_output_device, 0);

    rb_define_method(rb_cOutLoop, "[]=", ca_out_loop_data_assign, 2);
    rb_define_method(rb_cOutLoop, "start", ca_out_loop_data_start, 0);
    rb_define_method(rb_cOutLoop, "stop", ca_out_loop_data_stop, 0);
}
