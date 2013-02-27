require 'bud'
require 'lock'
# require 'lckmgr'

require 'test/unit'

class LockMgr
	include Bud
	include LockManager
end

class TestLockManager < Test::Unit::TestCase
	def setup
		@mgr = LockMgr.new(port: 12345)
		@mgr.run_bg
	end

	def tick(n=1)
		n.times { @mgr.tick }
	end

	def test_basic
		@mgr.sync_do {
			@mgr.request_lock <+ [[1, 'a', :S]]
			@mgr.request_lock <+ [[2, 'b', :X]]
			@mgr.request_lock <+ [[3, 'a', :X]]
		}
		tick 3
		assert_equal(2, @mgr.granted_locks.length)
	end
end