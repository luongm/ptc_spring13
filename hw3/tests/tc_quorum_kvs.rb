require 'rubygems'
require 'bud'
require 'test/unit'
require 'kvs/quorum_kvs'

class TestQuorum < Test::Unit::TestCase
  class Quorum
    include Bud
    include QuorumKVS
    state do
      periodic :tik, 0.1
    end
  end

  def setup
    @N = 3
    members = [
        [0, 'localhost:54320'],
        [1, 'localhost:54321'],
        [2, 'localhost:54322']
    ]
    @q = Array.new(@N)
    @N.times do |i|
      @q[i] = Quorum.new
      @q[i].run_bg
      members.each { |j| @q[i].sync_do { @q[i].add_member <= members } }
    end
  end

  def teardown
    @N.times do |i|
      @q[i].stop_bg
    end
  end

  def test_basic_config
    config = @q[0].sync_callback(:quorum_config, [[0.5, 0.6]], :qconfig)
    assert_equal([[0.5, 0.6]], config)
    assert_equal(true, @q[0].votebox.requirements.include?([5,6]))
  end

  def test_can_only_set_quorum_config_once
    config = @q[0].sync_callback(:quorum_config, [[0.5, 0.6]], :qconfig)
    config = @q[0].sync_callback(:quorum_config, [[0.4, 0.7]], :qconfig)
    assert_equal([[0.5, 0.6]], config)
    assert_equal(true, @q[0].votebox.requirements.include?([(@N*0.5).ceil,(@N*0.6).ceil]))
  end

  def test_rowo_one_node
    q = Quorum.new(:port => 54320)
    q.run_bg
    q.sync_callback(:add_member, [[0, 'localhost:54320']], :member)
    q.sync_callback(:quorum_config, [[0,0]], :qconfig)

    acks = q.sync_callback(:kvput, [[:c1, :k1, :r1, :v1]], :kv_acks)
    assert_equal([["r1"]], acks)
    acks = q.sync_callback(:kvget, [[:r2, :k1]], :kvget_response)
    assert_equal([["r2", "k1", "v1"]], acks)
    q.stop_bg
  end

  def test_rowo_three_nodes
    q1 = Quorum.new(:port => 54320)
    q2 = Quorum.new(:port => 54321)
    q3 = Quorum.new(:port => 54322)
    q1.run_bg
    q2.run_bg
    q3.run_bg
    q1.sync_callback(:add_member, [[0, 'localhost:54320'], [1, 'localhost:54321'], [2, 'localhost:54322']], :member)
    q2.sync_callback(:add_member, [[0, 'localhost:54320'], [1, 'localhost:54321'], [2, 'localhost:54322']], :member)
    q3.sync_callback(:add_member, [[0, 'localhost:54320'], [1, 'localhost:54321'], [2, 'localhost:54322']], :member)
    q1.sync_callback(:quorum_config, [[0,0]], :qconfig)
    q2.sync_callback(:quorum_config, [[0,0]], :qconfig)
    q3.sync_callback(:quorum_config, [[0,0]], :qconfig)

    acks = q1.sync_callback(:kvput, [[:c1, :k1, :r1, :v1]], :kv_acks)
    assert_equal([["r1"]], acks)
    acks = q2.sync_callback(:kvget, [[:r2, :k1]], :kvget_response)
    assert_equal([["r2", "k1", "v1"]], acks)
    acks = q3.sync_callback(:kvget, [[:r3, :k1]], :kvget_response)
    assert_equal([["r3", "k1", "v1"]], acks)

    q2.stop_bg
    q3.stop_bg

    acks = q1.sync_callback(:kvput, [[:c2, :k1, :r4, :v2]], :kv_acks)
    assert_equal([["r4"]], acks)
    acks = q1.sync_callback(:kvget, [[:r5, :k1]], :kvget_response)
    assert_equal([["r5", "k1", "v2"]], acks)
    q1.stop_bg
  end
end
