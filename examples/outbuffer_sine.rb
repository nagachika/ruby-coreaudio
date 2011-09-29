require "coreaudio"

dev = CoreAudio.default_output_device
#dev = CoreAudio.devices[3]
buf = dev.output_buffer(1024)

phase = Math::PI * 2.0 * 440.0 / dev.nominal_rate
th = Thread.start do
  i = 0
  loop do
    wav = Array.new(1024){|j| 0.4 * Math.sin(phase*(i+j))}
    i += 1024
    buf << wav
    p :write
  end
end

buf.start
sleep 2
buf.stop

th.kill
