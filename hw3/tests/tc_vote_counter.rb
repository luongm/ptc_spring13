require 'rubygems'
require 'bud'
require 'test/unit'
require '../voting/voting'

class TestVoteCounter < Test::Unit::TestCase
  class VoteBox
    include Bud
    include VoteCounter
    state do
      periodic :tik, 0.1
    end
  end

  def setup
    @vb = VoteBox.new #(port: 12345, trace: true)
    @vb.run_bg
    @vb.sync_do { @vb.set_requirements <+ [[:read, 3], [:write, 4]] }
  end

  def teardown
    @vb.stop
  end
  
  def test_set_requirements
    assert @vb.requirements.include?([:read, 3])
    assert @vb.requirements.include?([:write, 4])
  end

  def test_waiting_for_enough_reads
    @vb.sync_callback(:read_ack, [["localhost:54321", 1, :k1, 0, :v0]], :read_acks_received)
    @vb.sync_callback(:read_ack, [["localhost:54322", 1, :k1, 1, :v1]], :read_acks_received)
    assert @vb.read_result.empty?, "VoteBox cannot return read result yet"

    res = @vb.sync_callback(:read_ack, [["localhost:54323", 1, :k1, 2, :v2]], :read_result)
    assert !res.empty?, "VoteBox should have returned read_result now"
    assert res.include?([1, :k1, :v2]), "res is supposed to include [1, :k1, :v2] but it is #{res}"
  end

  def test_waiting_for_enough_writes
    @vb.sync_callback(:write_ack, [["localhost:54321", 2, :k1]], :write_acks_received)
    @vb.sync_callback(:write_ack, [["localhost:54322", 2, :k1]], :write_acks_received)
    @vb.sync_callback(:write_ack, [["localhost:54323", 2, :k1]], :write_acks_received)
    assert @vb.write_result.empty?, "VoteBox cannot return write result yet"

    res = @vb.sync_callback(:write_ack, [["localhost:54324", 2, :k1]], :write_result)
    assert !res.empty?, "VoteBox should have returned write_result now"
    assert res.include?([2]), "VoteBox should return an ack to the write's req_id of 2"
  end
end
