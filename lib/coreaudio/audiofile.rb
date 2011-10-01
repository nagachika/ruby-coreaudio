
require "dl"
require "dl/import"

module CoreAudio
  module AudioFile
    extend DL::Importer

    dlload "/System/Library/Frameworks/AudioToolbox.framework/Versions/Current/AudioToolbox"

    FSRef = struct(["char data[80]"])
    extern "int FSPathMakeRef(const char *, void *, void *)"

    AudioFileID = struct(["void *ptr"])
    ExtAudioFileRef = struct(["void *ptr"])

    # CFStringRef CFStringCreateWithCStringNoCopy (
    #   CFAllocatorRef alloc,
    #   const char *cStr,
    #   CFStringEncoding encoding,
    #   CFAllocatorRef contentsDeallocator);
    CFStringEncodingMacRoman = 0
    CFStringEncodingMacJapanese = 1
    extern "void *CFStringCreateWithCString(void *, const char *, int)"

    AudioFileWAVEType = 'WAVE'.unpack("N")[0]
    AudioFileAIFFType = 'AIFF'.unpack("N")[0]
    AudioFileMP3Type = "MPG3".unpack("N")[0]
    AudioFileM4AType = "m4af".unpack("N")[0]

    # OSStatus
    # AudioFileOpen(const struct FSRef *inFileRef,
    #               SInt8 inPermissions,
    #               AudioFileTypeID inFileTypeHint,
    #               AudioFileID *outAudioFile)
    extern "int AudioFileOpen(const void *, char, int, void **)"

    # OSStatus AudioFileClose(AudioFileID audioFile)
    extern "int AudioFileClose(void *)"

    # OSStatus
    # AudioFileCreate (const struct FSRef                *inParentRef,
    #                  CFStringRef                       inFileName,
    #                  AudioFileTypeID                   inFileType,
    #                  const AudioStreamBasicDescription *inFormat,
    #                  UInt32                            inFlags,
    #                  struct FSRef                      *outNewFileRef,
    #                  AudioFileID                       *outAudioFile)
    #
    extern "int AudioFileCreate(const void *, void *, int, void *, int, void *, void *)"

    # OSStatus AudioFormatGetProperty(AudioFormatPropertyID inPropertyID,
    #                                 UInt32 inSpecifierSize,
    #                                 const void *inSpecifier,
    #                                 UInt32 *ioPropertyDataSize,
    #                                 void *outPropertyData)
    extern "int AudioFormatGetProperty(int, int, const void *, void *, void *)"

    # AudioStreamBasicDescription
    # struct AudioStreamBasicDescription
    # {
    #   Float64 mSampleRate;
    #   UInt32  mFormatID;
    #   UInt32  mFormatFlags;
    #   UInt32  mBytesPerPacket;
    #   UInt32  mFramesPerPacket;
    #   UInt32  mBytesPerFrame;
    #   UInt32  mChannelsPerFrame;
    #   UInt32  mBitsPerChannel;
    #   UInt32  mReserved;
    # };
    AudioStreamBasicDescription = struct(["double mSampleRate",
                                         "int mFormatID",
                                         "int mFormatFlags",
                                         "int mBytesPerPacket",
                                         "int mFramesPerPacket",
                                         "int mBytesPerFrame",
                                         "int mChannelsPerFrame",
                                         "int mBitsPerChannel",
                                         "int mRserved"])

    # OSStatus ExtAudioFileWrapAudioFileID(AudioFileID inFileID,
    #                                      Boolean inForWriting,
    #                                      ExtAudioFileRef outExtAudioFile)
    extern "int ExtAudioFileWrapAudioFileID(void *, char, void *)"

    # OSStatus
    # ExtAudioFileCreateNew(const struct FSRef *inParentDir,
    #                       CFStringRef inFileName,
    #                       AudioFileTypeID inFileType,
    #                       const AudioStreamBasicDescription * inStreamDesc,
    #                       const AudioChannelLayout * inChannelLayout,
    #                       ExtAudioFileRef *outExtAudioFile)
    extern "int ExtAudioFileCreateNew(void *, void *, int, void *, void *, void *)"

    # OSStatus ExtAudioFileDispose(ExtAudioFileRef inExtAudioFile)
    extern "int ExtAudioFileDispose(void *)"

    # OSStatus AudioFileWrite(ExtAudioFileRef inExtAudioFile,
    #                         UInt32 inNumberFrames,
    #                         const AudioBufferList *ioData)
    extern "int ExtAudioFileWrite(void *, int, const void *)"

    # OSStatus AudioFileWriteAsync(ExtAudioFileRef inExtAudioFile,
    #                              UInt32 inNumberFrames,
    #                              const AudioBufferList *ioData)
    extern "int ExtAudioFileWriteAsync(void *, int, const void *)"

    # OSStatus ExtAudioFileSetProperty(ExtAudioFileRef inExtAudioFile,
    #                                  ExtAudioFilePropertyID inPropertyID,
    #                                  UInt32 inPropertyDataSize,
    #                                  const void *inPropertyData)
    extern "int ExtAudioFileSetProperty(void *, int, int, void *)"

    ExtAudioFileProperty_ClientDataFormat = 'cfmt'.unpack("N")[0]

    # struct AudioBufferList {
    #   UInt32 mNumberBuffers;
    #   AudioBuffer mBuffers[1];
    # }
    # struct AudioBuffer {
    #   UInt32 mNumberChannels;
    #   UInt32 mDataByteSize;
    #   void *mData;
    # }
    AudioBuffer = struct(["int mNumberChannels",
                         "int mDataByteSize",
                         "void *mData"])
    AudioBufferList = struct(["int mNumberBuffers",
                             "int mNumberChannels",
                             "int mDataByteSize",
                             "void *mData"])

    def save_wav(path, data, opt={})
      rate = opt[:rate] || 44100.0
      channel = opt[:channel] || 2
      encoding = opt[:filepath_encoding] || CFStringEncodingMacJapanese

      path = File.expand_path(path)
      fsref = FSRef.malloc
      ret = AudioFile.FSPathMakeRef(File.dirname(path), fsref, 0)
      unless ret == 0
        raise "coreaudio: FSPathMakeRef() fail to make directory path. (#{ret})"
      end
      file = AudioFile.CFStringCreateWithCString(0, File.basename(path), encoding)

      # output format (ASBD)
      outfmt = AudioStreamBasicDescription.malloc
      outfmt.mSampleRate = rate
      outfmt.mFormatID = "lpcm".unpack("N")[0]
      outfmt.mFormatFlags = 0x04|0x08
      outfmt.mBytesPerPacket = 2*channel
      outfmt.mFramesPerPacket = 1
      outfmt.mBytesPerFrame = 2*channel
      outfmt.mChannelsPerFrame = channel
      outfmt.mBitsPerChannel = 16

      # client format (ASBD)
      clientFormat = AudioStreamBasicDescription.malloc
      clientFormat.mSampleRate = rate
      clientFormat.mFormatID = "lpcm".unpack("N")[0]
      clientFormat.mFormatFlags = 0x04|0x08
      clientFormat.mBytesPerPacket = 2*channel
      clientFormat.mFramesPerPacket = 1
      clientFormat.mBytesPerFrame = 2*channel
      clientFormat.mChannelsPerFrame = channel
      clientFormat.mBitsPerChannel = 16

      File.unlink(path) rescue nil

      outfsref = FSRef.malloc
      extfileref = ExtAudioFileRef.malloc
      ret = AudioFile.ExtAudioFileCreateNew(fsref, file, AudioFileWAVEType,
                                            outfmt, nil, extfileref)
      unless ret == 0
        raise "coreaudio: ExtAudioFileCreateNew() fail to create AudioFile. (#{ret})"
      end

      ret = AudioFile.ExtAudioFileSetProperty(extfileref.ptr, ExtAudioFileProperty_ClientDataFormat, AudioStreamBasicDescription.size, clientFormat)
      unless ret == 0
        raise "coreaudio: ExtAudioFileSetProperty() fail to wrap AudioFile. (#{ret})"
      end

      bufferlist = AudioBufferList.malloc
      bufferlist.mNumberBuffers = 1
      bufferlist.mNumberChannels = channel
      bufferlist.mDataByteSize = 2*data.size
      if ( data[0].is_a?(Float) )
        bufferlist.mData = data.map{|i| (i*0x7fff).round}.pack("s*")
      else
        bufferlist.mData = data.pack("s*")
      end

      ret = AudioFile.ExtAudioFileWrite(extfileref.ptr, data.size/channel, bufferlist)
      unless ret == 0
        raise "coreaudio: ExtAudioFileWrite() fail to write AudioFile. (#{ret})"
      end

      AudioFile.ExtAudioFileDispose(extfileref.ptr)
      nil
    end
    module_function :save_wav
  end
end
