require 'rubygems'
require 'bud'
require 'test/unit'
require 'xact_kvs'

class XKVS
	include Bud
	include TwoPLTransactionalKVS
end

class TestTransactionalKVS < Test::Unit::TestCase
	def setup
		@xkvs = XKVS.new
	end

	def tick(n=1)
		n.times { @xkvs.tick }
	end

	def test_success_put_then_get
		@xkvs.sync_do do
			@xkvs.xput <+ [[1, 'k1', 1, 'v1']]
		end
		tick
		@xkvs.xput_response.each do |res|
			assert_equal(1, res.xid)
			assert_equal('k1', res.key)
			assert_equal(1, res.reqid)
		end

		assert(1, @xkvs.granted_locks.length);
		@xkvs.sync_do do
			@xkvs.end_xact <+ [[1]]
		end

		@xkvs.sync_do do
			@xkvs.xget <+ [[1, 'k1', 1]]
		end
		tick
		@xkvs.xget_response.each do |res|
			assert_equal(1, res.xid)
			assert_equal('k1', res.key)
			assert_equal(1, res.reqid)
			assert_equal('v1', res.data)
		end
	end

	def teardown
		@xkvs.stop unless @xkvs.nil?
	end
end