require 'rubygems'
require 'bud'
require 'xact_kvs'
require 'test/unit'

class KVS
  include Bud
  include TwoPLTransactionalKVS 

  state do
  end

  bloom do
    stdio <~ granted_locks.inspected
  end

end

class TestKVS < Test::Unit::TestCase
  @kvs = nil

  def setup
    @kvs = KVS.new()
    @kvs.run_bg
  end

  def teardown
    @kvs.stop_bg
  end

  def tick(n = 4)
    n.times { @kvs.sync_do }
  end

  def test_success_put_then_get
    @kvs.sync_do do
      @kvs.xput <+ [[1, 'k1', 1, 'v1']]
    end
    tick
    @kvs.xput_response.each do |res|
      assert_equal(1, res.xid)
      assert_equal('k1', res.key)
      assert_equal(1, res.reqid)
    end

    assert(1, @kvs.granted_locks.length);
    @kvs.sync_do do
      @kvs.end_xact <+ [[1]]
    end

    @kvs.sync_do do
      @kvs.xget <+ [[1, 'k1', 1]]
    end
    tick
    @kvs.xget_response.each do |res|
      assert_equal(1, res.xid)
      assert_equal('k1', res.key)
      assert_equal(1, res.reqid)
      assert_equal('v1', res.data)
    end
  end


  def test_basic_put
    @kvs.sync_do { @kvs.xput <+ [["A", "foo", "1", "bar"]] }
    tick 2

    assert_equal(@kvs.granted_locks.length, 1)
    @kvs.granted_locks.each do |l|
      if l.resource == "foo"
        assert_equal(l.xid, "A")
        assert_equal(l.mode, :X)        
      end
    end

    assert_equal(@kvs.lock_status.length, 1)

    assert_equal(@kvs.kvput.length, 1)
    @kvs.kvput.each do |put|
      assert_equal(put.reqid, "1")
    end

    assert_equal(@kvs.xput_response.length, 1)
    @kvs.xput_response.each do |responses|
      assert_equal(responses.xid, "A")
      assert_equal(responses.key, "foo")
      assert_equal(responses.reqid, "1")
    end
    
    assert_equal(@kvs.kvstate.length, 1)
    @kvs.kvstate.each do |kv|
      assert_equal(kv.key, "foo")
      assert_equal(kv.value, "bar")
    end
  end

  def test_basic_get
    # @kvs.stop_bg
    # @kvs = KVS.new(:trace => true, :port => 12345)
    @kvs.sync_do { @kvs.xput <+ [["A", "foo", "1", "bar"]] }
    @kvs.sync_do { @kvs.xget <+ [["A", "foo", "1"]] }
    tick

    assert_equal(@kvs.granted_locks.length, 1)
    @kvs.granted_locks.each do |l|
      if l.resource == "foo"
        assert_equal(l.xid, "A")
        assert_equal(l.mode, :X)        
      end
    end

    assert_equal(@kvs.kvstate.length, 1)
    @kvs.kvstate.each do |kv|
      assert_equal(kv.key, "foo")
      assert_equal(kv.value, "bar")
    end

    assert_equal(@kvs.kvget.length, 1)
    @kvs.kvget.each do |put|
      assert_equal(put.reqid, "1")
    end

    assert_equal(@kvs.xput_response.length, 1)
    @kvs.xget_response.each do |responses|
      assert_equal(responses.xid, "A")
      assert_equal(responses.key, "foo")
      assert_equal(responses.reqid, "1")
      assert_equal(responses.data, "bar")
    end

    assert_equal(@kvs.get_queue.length, 0)
    
    @kvs.kvget.each do |get|
      assert_equal(get.key, "foo")
    end
  end

  # Testing a conflict serializable schedule
  def test_conflict_serialiability
    # Populate kvstate with two key-values
    @kvs.sync_do do
      @kvs.xput <+ [["A", "foo", 1, "bar"]]
      @kvs.xput <+ [["A", "foo2", 1, "baz"]]
    end

    # @kvs.sync_callback(:xput, [["A", "foo", 1, "bar"]], :xput_response)
    # @kvs.sync_callback(:xput, [["A", "foo2", 1, "baz"]], :xput_response)
    @kvs.sync_do { @kvs.end_xact <+ [["A"]] }
    tick 4

    assert_equal(@kvs.granted_locks.length, 0)
    # T1 does a get and a put on "foo"
    @kvs.sync_callback(:xget, [["T1", "foo", 2]], :xget_response)
    @kvs.sync_callback(:xput, [["T1", "foo", 3, "foo_a"]], :xput_response)
    tick
    
    # T1 should have obtained a :X lock on "foo"
    assert_equal(@kvs.granted_locks.length, 1)
    @kvs.granted_locks.each do |l|
      if l.resource == "foo"
        assert_equal(l.xid, "T1")
        assert_equal(l.mode, :X)        
      end
    end
    
    # kvstate should have the updated value for "foo" but the old value for "foo2"
    assert_equal(@kvs.kvstate.length, 2)
    @kvs.kvstate.each do |kv|
      if (kv.key == "foo")
        assert_equal(kv.value, "foo_a")        
      end
      if (kv.key == "foo2")
        assert_equal(kv.value, "baz")
      end
    end

    # T2 tries to do a get and put for "foo"
    @kvs.sync_do { @kvs.xget <+ [["T2", "foo", "4"]] }
    @kvs.sync_do { @kvs.xput <+ [["T2", "foo", "5", "foo_b"]] }

    
    # T2 should be blocked, since T1 has a :X lock on "foo"
    assert_equal(@kvs.granted_locks.length, 1)
    @kvs.granted_locks.each do |l|
      if l.resource == "foo"
        assert_equal(l.xid, "T1")
        assert_equal(l.mode, :X)        
      end
    end

    # T1 does a get and put on "foo2"
    @kvs.sync_callback(:xget, [["T1", "foo2", 6]], :xget_response)
    @kvs.sync_callback(:xput, [["T1", "foo2", 7, "foo2_a"]], :xput_response)
    tick(1)

    # T1 should have a :X lock on "foo" and "foo2"
    assert_equal(@kvs.granted_locks.length, 2)
    @kvs.granted_locks.each do |l|
      if l.resource == "foo"
        assert_equal(l.xid, "T1")
        assert_equal(l.mode, :X)        
      end
      if l.resource == "foo2"
        assert_equal(l.xid, "T1")
        assert_equal(l.mode, :X)        
      end
    end

    # kvstate should have the T1's updated values for "foo" and "foo2"
    assert_equal(@kvs.kvstate.length, 2)
    @kvs.kvstate.each do |kv|
      if (kv.key == "foo")
        assert_equal(kv.value, "foo_a")        
      end
      if (kv.key == "foo2")
        assert_equal(kv.value, "foo2_a")
      end
    end

    # End T1
    @kvs.sync_do { @kvs.end_xact <+ [["T1"]] }
    tick

    # Since T2 had been trying to do a get and put on "foo" - it should obtain a :X lock for "foo" now
    assert_equal(@kvs.granted_locks.length, 1)
    @kvs.granted_locks.each do |l|
      if l.resource == "foo"
        assert_equal(l.xid, "T2")
        assert_equal(l.mode, :X)        
      end
    end
    
    # kvstate should have T2's value for "foo" and T1's for "foo2"
    assert_equal(@kvs.kvstate.length, 2)
    @kvs.kvstate.each do |kv|
      if (kv.key == "foo")
        assert_equal(kv.value, "foo_b")        
      end
      if (kv.key == "foo2")
        assert_equal(kv.value, "foo2_a")
      end
    end
    
    # T2 does a get and put on "foo2"
    @kvs.sync_callback(:xput, [["T2", "foo2_b", 5, "foo2_b"]], :xput_response)
    @kvs.sync_callback(:xget, [["T2", "foo2_b", 4]], :xget_response)
    tick

    # T2 should have a :X lock on "foo" and "foo2"
    assert_equal(@kvs.granted_locks.length, 2)
    @kvs.granted_locks.each do |l|
      if l.resource == "foo"
        assert_equal(l.xid, "T2")
        assert_equal(l.mode, :X)        
      end
      if l.resource == "foo2"
        assert_equal(l.xid, "T2")
        assert_equal(l.mode, :X)        
      end
    end
    
    # kvstate should have T2's updated values for "foo" and "foo2" and "foo2_b"
    assert_equal(@kvs.kvstate.length, 3)
    @kvs.kvstate.each do |kv|
      if (kv.key == "foo")
        assert_equal(kv.value, "foo_b")        
      end
      if (kv.key == "foo2")
        assert_equal(kv.value, "foo2_a")
      end
      if (kv.key == "foo2_b")
        assert_equal(kv.value, "foo2_b")
      end
    end

    # End T2
    @kvs.sync_do { @kvs.end_xact <+ [["T2"]] }
    tick
    
    # All granted_locks should have been released
    assert_equal(@kvs.granted_locks.length, 0)
  end

  def teardown
  	@xkvs.stop unless @xkvs.nil?
  end
end