require 'mkmf'

$CFLAGS = "-ObjC"

dir_config("coreaudio")
if have_framework("CoreAudio")
  create_makefile("coreaudio/coreaudio_ext")
end
