
require "coreaudio"
require "coreaudio/audiofile"

dev = CoreAudio.default_input_device
buf = dev.input_buffer(1024)

input_wave = []
th = Thread.start{ loop { input_wave +=  buf.read(22050) } }
buf.start;
$stdout.print "RECORDING..."
$stdout.flush
sleep 5;
buf.stop
$stdout.puts "done."
th.kill.join

puts "#{input_wave.size} samples read."

CoreAudio::AudioFile.save_wav("aaa.wav", input_wave)
