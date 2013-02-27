require 'rubygems'
require 'bud'
require 'lock'
require 'test/unit'

class LockMgr
	include Bud
  #include TwoPhaseLockMgr
	include LockManager
  state do
	end

	bloom do
	end
end

class TestLockManager < Test::Unit::TestCase
  def tick(n)
    n.times {@ml.sync_do}
  end

  @ml = nil
  def test_sharedlock_ok
    @ml = LockMgr.new(:port => 12345)
    @ml.sync_do {
      @ml.request_lock <+ [["1", "A", :S]] 
    }
    #@ml.tick
    3.times {@ml.sync_do}      
    sleep 2

    @ml.granted_locks.each do |l|
      if l.resource == "A"
        assert_equal(l.xid, "1")
        assert_equal(l.mode, :S)
      end
    end
    assert_equal(@ml.granted_locks.length, 1)
  end
  
  def test_sharedlock_bad
    @ml = LockMgr.new(:port => 12345)
    #Trying to acquire a :S lock on a resource that 
    # another Xact has a :X lock on
    @ml.sync_do { 
      @ml.request_lock <+ [ ["1", "a", :S] ] 
      @ml.request_lock <+ [ ["2", "b", :X] ] 
      @ml.request_lock <+ [ ["3", "a", :X] ] 
    }

    tick(5)

    #@ml.granted_locks.each do |l|
    #  if l.resource == "B"
    #    assert_equal(l.xid, "2")
    #    assert_equal(l.mode, :X)        
    #  end
    #end
    assert_equal(@ml.granted_locks.length, 2)
  end

  def test_exclusivelock_ok
    @ml = LockMgr.new(:port => 12345)

    # Acquire an exclusive lock
    @ml.sync_do { @ml.request_lock <+ [ ["2", "B", :X] ] }
    tick(1)
    @ml.granted_locks.each do |l|
      if l.resource == "B"
        assert_equal(l.xid, "2")
        assert_equal(l.mode, :X)        
      end
    end
    assert_equal(@ml.granted_locks.length, 1)
  end

  def test_locks_bad
    @ml = LockMgr.new(:port => 12345)

    # Can't have both a shared and exclusive lock on a resource
    @ml.sync_do { @ml.request_lock <+ [ ["1", "A", :S], ["3", "A", :X] ] }
    tick(1)

    assert_equal(@ml.granted_locks.length, 1)
    assert_equal(@ml.waiting_locks.length, 1)
  end

  def test_locks_ok
    @ml = LockMgr.new(:port => 12345)

    # Multiple Xacts can acquire a shared lock on a resource
    @ml.sync_do { @ml.request_lock <+ [ ["4", "C", :S],["5", "C", :S] ] }
    tick(2)

    acquiredLocks = Array.new
    @ml.granted_locks.each do |l|
      if l.resource == "C"
        assert_equal(l.mode, :S)        
        assert(["4", "5"].include?(l.xid))        
        acquiredLocks << l.xid
      end
    end
    acquiredLocks.sort!
    assert_equal(acquiredLocks.length, 2)
    assert_equal(acquiredLocks[1], "5")
    assert_equal(acquiredLocks[0], "4")
  end
  
  def test_releaselock_simple
    @ml = LockMgr.new(:port => 12345)
    @ml.sync_do { @ml.request_lock <+ [ ["10", "G", :X] ] }
    @ml.sync_do { @ml.end_xact <+ [ ["10"] ] }
    @ml.sync_do { @ml.request_lock <+ [ ["11", "G", :S] ] }
    tick(1)

    @ml.granted_locks.each do |l|
      if l.resource == "G"
        assert_equal(l.mode, :S)        
        assert_equal(l.xid, "11")        
      end
    end
  end

  def test_releaselock 
    # Acquire many :S granted_locks, end one Xact 
    # Try to acquire a :X lock - fails
    # Try to acquire a :S lock - succeeds
    
    @ml = LockMgr.new(:port => 12345)
    @ml.sync_do { @ml.request_lock <+ [ ["12", "J", :S], ["13", "H", :S] ] }
    @ml.sync_do { @ml.end_xact <+ [ ["12"] ] }
    @ml.sync_do { @ml.request_lock <+ [ ["14", "J", :X],["15", "H", :S] ] }
    tick(1)

    acquiredLocks = Array.new
    @ml.granted_locks.each do |l|
      if l.resource == "H"
        assert_equal(l.mode, :S)        
        assert(["13", "15"].include?(l.xid))        
      elsif l.resource == "J"
        assert_equal(l.mode, :X)        
        assert(["14"].include?(l.xid))        
      end
      acquiredLocks << l.xid
    end

    acquiredLocks.sort!
    assert_equal(acquiredLocks.length, 3)
    assert_equal(acquiredLocks.at(0), "13")
    assert_equal(acquiredLocks.at(1), "14")
    assert_equal(acquiredLocks.at(2), "15")
  end

  def test_releaselock_upgrade
    # End Xact and perform a Lock upgrade
    @ml = LockMgr.new(:port => 12345)
    @ml.sync_do { @ml.request_lock <+ [ ["16", "I", :S], ["17", "I", :S] ] }
    @ml.sync_do { @ml.end_xact <+ [ ["16"] ] }
    @ml.sync_do { @ml.request_lock <+ [ ["17", "I", :X] ] }
    tick(1)

    @ml.granted_locks.each do |l|
      if l.resource == "I"
        assert_equal(l.xid, "17")
        assert_equal(l.mode, :S)        
      end
    end
  end

  def test_suddenend
    # End a Xact when it still has pending granted_locks 
    @ml = LockMgr.new(:port => 12345)
    @ml.sync_do { @ml.request_lock <+ [ ["18", "I", :S], ["19", "I", :S], ["19", "J", :X] ] }
    tick(1)
    @ml.sync_do { @ml.request_lock <+ [ ["19", "I", :X], ["20", "J", :S] ] }
    tick(1)

    assert_equal(@ml.granted_locks.length, 3)
    assert_equal(@ml.waiting_locks.length, 2)

    @ml.sync_do { @ml.end_xact <+ [ ["19"] ] }
    tick(2)

    @ml.granted_locks.each do |l|
      if l.resource == "I"
        assert_equal(l.xid, "18")
        assert_equal(l.mode, :S)        
      end
    end
    assert_equal(@ml.granted_locks.length, 2)
    assert_equal(@ml.waiting_locks.length, 0)
  end

  def test_blocking
    @ml = LockMgr.new(:port => 12345)
    res = @ml.sync_callback(:request_lock, [[1, "foo", :S]], :lock_status)
    res = @ml.sync_callback(:request_lock, [[1, "bar", :S]], :lock_status)

    assert_equal([1, "bar", :OK], res.first)

    q = Queue.new
    @ml.register_callback(:lock_status) do |l|
      l.each do |row|
        if row.xid == 2
          q.push row
        end
      end
    end


    @ml.register_callback(:lock_status) do |l|
      l.each do |row|
        if row.xid == 3
          @ml.sync_do{ @ml.end_xact <+ [[3]]}
          @ml.sync_do
        end
      end
    end


    @ml.sync_do{ @ml.request_lock <+ [[2, "foo", :S]]}
    @ml.sync_do{ @ml.request_lock <+ [[3, "foo", :S]]}

    assert_equal(@ml.granted_locks.length, 3)
    @ml.sync_do { @ml.end_xact <+ [[1]]}
    @ml.sync_do
    assert_equal(@ml.granted_locks.length, 1)

    row = q.pop
    assert_equal([2, "foo", :OK], row)
    assert(true)
  end

end
