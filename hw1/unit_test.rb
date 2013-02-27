require 'rubygems'
require 'bud'
require 'delivery/reliable'

require 'fifo'
require 'test/unit'

class FC
  include Bud
  include FIFODelivery

  state do
    table :timestamped, [:time, :ident, :src, :payload]
  end

  bloom do
    timestamped <= pipe_out {|c| [budtime, c.ident, c.src, c.payload]}
  end

end


class TestFIFO < Test::Unit::TestCase
  def workload(sender)
    send_host = "localhost:54321"
    recv_host = "localhost:12345"
    sender.sync_do { sender.pipe_in <+ [ [recv_host, send_host, 3, "qux"] ] }
    sender.sync_do { sender.pipe_in <+ [ [recv_host, send_host, 1, "bar"] ] }
    sender.sync_do { sender.pipe_in <+ [ [recv_host, send_host, 0, "foo"] ] }
    sender.sync_do { sender.pipe_in <+ [ [recv_host, send_host, 2, "baz"] ] }
    return 4
  end

  def workload2(sender1, sender2)
    send_host1 = "localhost:65432"
    send_host2 = "localhost:76543"
    recv_host = "localhost:23456"
    sender1.sync_do { sender1.pipe_in <+ [ [recv_host, send_host1, 3, "qux"] ] }
    sender1.sync_do { sender1.pipe_in <+ [ [recv_host, send_host1, 1, "bar"] ] }
    sender1.sync_do { sender1.pipe_in <+ [ [recv_host, send_host1, 0, "foo"] ] }
    sender1.sync_do { sender1.pipe_in <+ [ [recv_host, send_host1, 2, "baz"] ] }

    sender2.sync_do { sender2.pipe_in <+ [ [recv_host, send_host2, 2, "ghi"] ] }
    sender2.sync_do { sender2.pipe_in <+ [ [recv_host, send_host2, 1, "def"] ] }
    sender2.sync_do { sender2.pipe_in <+ [ [recv_host, send_host2, 0, "abc"] ] }
    sender2.sync_do { sender2.pipe_in <+ [ [recv_host, send_host2, 3, "jkl"] ] }
    return 8
  end

  def workload3(senders)
    send_hosts = Array.new(senders.length) {|i| "localhost:"+(11111*(i+1)).to_s}
    recv_host = "localhost:34567"
    senders.each_index do |i|
      senders[i].sync_do {senders[i].pipe_in <+ [ [recv_host, send_hosts[i], 1, "bbb"] ] }
      senders[i].sync_do {senders[i].pipe_in <+ [ [recv_host, send_hosts[i], 4, "eee"] ] }
      senders[i].sync_do {senders[i].pipe_in <+ [ [recv_host, send_hosts[i], 0, "aaa"] ] }
      senders[i].sync_do {senders[i].pipe_in <+ [ [recv_host, send_hosts[i], 3, "ddd"] ] }
      senders[i].sync_do {senders[i].pipe_in <+ [ [recv_host, send_hosts[i], 2, "ccc"] ] }
    end
    return senders.length*5
  end

  def check_receiver(receiver, n)
    receiver.sync_do do
      timestamps = receiver.timestamped
      timestamps.each do |t|
        timestamps.each do |t2|
          if t.ident < t2.ident and t.src == t2.src
            assert(t.time < t2.time, "Message not in order: #{t.inspect} should comes before #{t2.inspect}")
          end
        end
      end
      assert_equal(n, timestamps.length, "Sent #{n} but received #{receiver.timestamped.length} instead")
    end
  end

  def test_single_sender_single_receiver
    sender = FC.new(port: 54321)
    receiver = FC.new(port: 12345)

    sender.run_bg
    receiver.run_bg
    n = workload(sender)
    sleep 1
    n.times {receiver.sync_do}

    check_receiver(receiver, n)
  end

  def test_two_senders_single_receiver
    sender1 = FC.new(port: 65432)
    sender2 = FC.new(port: 76543)
    receiver = FC.new(port: 23456)

    sender1.run_bg
    sender2.run_bg
    receiver.run_bg
    n = workload2(sender1, sender2)
    sleep 1
    n.times {receiver.sync_do}

    check_receiver(receiver, n)
  end

  def test_x_senders_single_receiver
    x = 9
    senders = Array.new(x) {|i| FC.new(port: 11111*(i+1))}
    receiver = FC.new(port:34567)

    senders.each {|sender| sender.run_bg}
    receiver.run_bg
    n = workload3(senders)
    sleep 4
    n.times {receiver.sync_do}

    check_receiver(receiver, n)
  end
end