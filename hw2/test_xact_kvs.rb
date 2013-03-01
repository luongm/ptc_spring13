require 'rubygems'
require 'bud'
require 'xact_kvs'
require 'test/unit'

class XKVS
	include Bud
	include TwoPLTransactionalKVS 
end

class TestKVS < Test::Unit::TestCase
	@xkvs = nil

	def setup
		@xkvs = XKVS.new
		@xkvs.run_bg
	end

	def teardown
		@xkvs.stop_bg
	end

	def tick(n = 1)
		n.times { @xkvs.sync_do }
	end

	def test_success_put_then_get
		@xkvs.sync_do do
			@xkvs.xput <+ [[1, 'k1', 1, 'v1']]
		end
		tick

		assert_equal(1, @xkvs.xput_response.length)
		@xkvs.xput_response.each do |res|
			assert_equal(1, res.xid)
			assert_equal('k1', res.key)
			assert_equal(1, res.reqid)
		end

		assert(1, @xkvs.lckmgr.granted_locks.length);
		@xkvs.sync_do do
			@xkvs.end_xact <+ [[1]]
		end

		@xkvs.sync_do do
			@xkvs.xget <+ [[1, 'k1', 1]]
		end
		tick
		assert(1, @xkvs.xget_response.length)
		@xkvs.xget_response.each do |res|
			assert_equal(1, res.xid)
			assert_equal('k1', res.key)
			assert_equal(1, res.reqid)
			assert_equal('v1', res.data)
		end
	end


	def test_internal_state_of_put
		@xkvs.sync_do { @xkvs.xput <+ [["A", "foo", "1", "bar"]] }
		tick
		assert_equal(@xkvs.kvs.kvput.length, 1)
		@xkvs.kvs.kvput.each do |put|
			assert_equal(put.reqid, "1")
		end

		assert_equal(@xkvs.xput_response.length, 1)
		@xkvs.xput_response.each do |responses|
			assert_equal(responses.xid, "A")
			assert_equal(responses.key, "foo")
			assert_equal(responses.reqid, "1")
		end
		
		assert_equal(@xkvs.lock_status.length, 1)
		tick
		assert_equal(1, @xkvs.lckmgr.granted_locks.length)
		@xkvs.lckmgr.granted_locks.each do |l|
			if l.resource == "foo"
				assert_equal(l.xid, "A")
				assert_equal(l.mode, :X)				
			end
		end

		assert_equal(@xkvs.kvs.kvstate.length, 1)
		@xkvs.kvs.kvstate.each do |kv|
			assert_equal(kv.key, "foo")
			assert_equal(kv.value, "bar")
		end
	end

	def test_internal_state_of_get
		@xkvs.sync_do { @xkvs.xput <+ [["A", "foo", "1", "bar"]] }
		@xkvs.sync_do { @xkvs.xget <+ [["A", "foo", "1"]] }

		assert_equal(@xkvs.kvs.kvget.length, 1)
		@xkvs.kvs.kvget.each do |get|
			assert_equal("1", get.reqid)
			assert_equal("foo", get.key)
		end

		assert_equal(@xkvs.xput_response.length, 1)
		@xkvs.xget_response.each do |responses|
			assert_equal("A", responses.xid)
			assert_equal("foo", responses.key)
			assert_equal("1", responses.reqid)
			assert_equal("bar", responses.data)
		end

		tick

		assert_equal(1, @xkvs.lckmgr.granted_locks.length)
		@xkvs.lckmgr.granted_locks.each do |l|
			if l.resource == "foo"
				assert_equal("A", l.xid)
				assert_equal(:X, l.mode)
			end
		end

		assert_equal(@xkvs.kvs.kvstate.length, 1)
		@xkvs.kvs.kvstate.each do |kv|
			assert_equal(kv.key, "foo")
			assert_equal(kv.value, "bar")
		end

		assert_equal(@xkvs.get_requests.length, 0)
	end

	# Testing a conflict serializable schedule
	def test_conflict_serializability
		# Populate kvs.kvstate with two key-values
		@xkvs.sync_do do
			@xkvs.xput <+ [["A", "foo", 1, "bar"]]
			@xkvs.xput <+ [["A", "foo2", 1, "baz"]]
		end
		tick
		assert_equal(2, @xkvs.xput_response.length)

		@xkvs.sync_do { @xkvs.end_xact <+ [["A"]] }
		tick
		assert_equal(0, @xkvs.lckmgr.granted_locks.length)

		# T1 does a get and a put on "foo"
		@xkvs.sync_do { @xkvs.xget <+ [["T1", "foo", 2]] }
		@xkvs.sync_do { @xkvs.xput <+ [["T1", "foo", 3, "foo_a"]] }
		tick 2
		# T1 should have obtained a :X lock on "foo"
		assert_equal(1, @xkvs.lckmgr.granted_locks.length)
		@xkvs.lckmgr.granted_locks.each do |l|
			if l.resource == "foo"
				assert_equal("T1", l.xid)
				assert_equal(:X, l.mode)				
			end
		end
		
		# kvs.kvstate should have the updated value for "foo" but the old value for "foo2"
		assert_equal(2, @xkvs.kvs.kvstate.length, 2)
		@xkvs.kvs.kvstate.each do |kv|
			assert_equal("foo_a", kv.value) if kv.key == "foo"
			assert_equal("baz", kv.value) if kv.key == "foo2"
		end

		# T2 tries to do a get and put for "foo"
		@xkvs.sync_do { @xkvs.xget <+ [["T2", "foo", 4]] }
		@xkvs.sync_do { @xkvs.xput <+ [["T2", "foo", 5, "foo_b"]] }
		tick
		
		# T2 should be blocked, since T1 has a :X lock on "foo"
		assert_equal(1, @xkvs.lckmgr.granted_locks.length)
		assert_equal(2, @xkvs.lckmgr.waiting_locks.length)
		@xkvs.lckmgr.granted_locks.each do |l|
			if l.resource == "foo"
				assert_equal(l.xid, "T1")
				assert_equal(l.mode, :X)				
			end
		end

		# T1 does a get and put on "foo2"
		@xkvs.sync_do { @xkvs.xget <+ [["T1", "foo2", 6]] }
		@xkvs.sync_do { @xkvs.xput <+ [["T1", "foo2", 7, "foo2_a"]] }
		tick 2

		# T1 should have a :X lock on "foo" and "foo2"
		assert_equal(@xkvs.lckmgr.granted_locks.length, 2)
		@xkvs.lckmgr.granted_locks.each do |l|
			if l.resource == "foo"
				assert_equal("T1", l.xid)
				assert_equal(:X, l.mode)				
			end
			if l.resource == "foo2"
				assert_equal("T1", l.xid)
				assert_equal(:X, l.mode)				
			end
		end

		# kvs.kvstate should have the T1's updated values for "foo" and "foo2"
		assert_equal(@xkvs.kvs.kvstate.length, 2)
		@xkvs.kvs.kvstate.each do |kv|
			if (kv.key == "foo")
				assert_equal(kv.value, "foo_a")				
			end
			if (kv.key == "foo2")
				assert_equal(kv.value, "foo2_a")
			end
		end

		# End T1
		@xkvs.sync_do { @xkvs.end_xact <+ [["T1"]] }
		tick 3 # 3 ticks required to put in the read lock and then upgrade to write lock

		# Since T2 had been trying to do a get and put on "foo" - it should obtain a :X lock for "foo" now
		assert_equal(1, @xkvs.lckmgr.granted_locks.length)
		@xkvs.lckmgr.granted_locks.each do |l|
			if l.resource == "foo"
				assert_equal("T2", l.xid)
				assert_equal(:X, l.mode)				
			end
		end
		
		# kvs.kvstate should have T2's value for "foo" and T1's for "foo2"
		assert_equal(@xkvs.kvs.kvstate.length, 2)
		@xkvs.kvs.kvstate.each do |kv|
			if (kv.key == "foo")
				assert_equal("foo_b", kv.value)
			end
			if (kv.key == "foo2")
				assert_equal("foo2_a", kv.value)
			end
		end
		
		# T2 does a get and put on "foo2"
		@xkvs.sync_do { @xkvs.xput <+ [["T2", "foo2_b", 5, "foo2_b"]] }
		@xkvs.sync_do { @xkvs.xget <+ [["T2", "foo2_b", 4]] }
		tick

		# T2 should have a :X lock on "foo" and "foo2"
		assert_equal(2, @xkvs.lckmgr.granted_locks.length)
		assert_equal(1, @xkvs.lckmgr.waiting_locks.length)
		tick
		assert_equal(0, @xkvs.lckmgr.waiting_locks.length)
		@xkvs.lckmgr.granted_locks.each do |l|
			if l.resource == "foo"
				assert_equal("T2", l.xid)
				assert_equal(:X, l.mode)				
			end
			if l.resource == "foo2"
				assert_equal("T2", l.xid)
				assert_equal(:X, l.mode)				
			end
		end
		
		# kvs.kvstate should have T2's updated values for "foo" and "foo2" and "foo2_b"
		assert_equal(@xkvs.kvs.kvstate.length, 3)
		@xkvs.kvs.kvstate.each do |kv|
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
		@xkvs.sync_do { @xkvs.end_xact <+ [["T2"]] }
		tick
		
		# All lckmgr.granted_locks should have been released
		assert_equal(@xkvs.lckmgr.granted_locks.length, 0)
	end

	def teardown
		@xkvs.stop unless @xkvs.nil?
	end
end