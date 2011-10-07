#ifndef COREAUDIO_H
#define COREAUDIO_H 1

extern VALUE rb_mCoreAudio;
extern VALUE rb_mAudioFile;

extern void Init_coreaudio_audiofile(void);

/*-- Utility Macros --*/
#define CROPF(F) ((F) > 1.0 ? 1.0 : (((F) < -1.0) ? -1.0 : (F)))
#define FLOAT2SHORT(F) ((short)(CROPF(F)*0x7FFF))
#define SHORT2FLOAT(S) ((double)(S) / 32767.0)

#endif
