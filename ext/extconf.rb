require 'mkmf'

$CFLAGS = "-ObjC"

dir_config("coreaudio")
if have_framework("CoreAudio") and
   have_framework("AudioToolBox") and
   have_framework("CoreFoundation") and
   have_framework("Cocoa")
  create_makefile("coreaudio/coreaudio_ext")
end
