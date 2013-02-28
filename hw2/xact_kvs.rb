require 'kvs'
require 'lckmgr'

# NOTE: can ignore XactKVSProtocol.reqid and KVSProtocol.client for hw2

module XactKVSProtocol
	state do
		interface input, :xput, [:xid, :key, :reqid] => [:data]
		interface input, :xget, [:xid, :key, :reqid]
    	interface output, :xget_response, [:xid, :key, :reqid] => [:data]
		interface output, :xput_response, [:xid, :key, :reqid]
	end
end

module TwoPLTransactionalKVS
	include XactKVSProtocol
	include BasicKVS
	include TwoPhaseLockMgr

	state do
		table :get_requests, [:xid, :key, :reqid]
		table :put_requests, [:xid, :key, :reqid] => [:data]

		scratch :get_ready, [:xid, :key, :reqid]
		scratch :put_ready, [:xid, :key, :reqid] => [:data]

	end

	bloom :recv_get do
		get_requests <= xget
		request_lock <+ xget {|x| [x.xid, x.key, :S] }
	end

	bloom :recv_put do
		put_requests <= xput
		request_lock <+ xput {|x| [x.xid, x.key, :X] }
	end

	bloom :done_get do
		get_ready <= (lock_status * get_requests).pairs(:xid => :xid, :resource => :key) { |s, r| r }

		# Send get request to BasicKVS
		kvget <= get_ready {|g| [g.reqid, g.key] }
		xget_response <= (kvget_response * get_requests).pairs(:key => :key, :reqid => :reqid) { |res, req|
			[req.xid, res.key, res.reqid, res.value]
		}

		# Remove get requests already finished
		get_requests <- get_ready
	end

	bloom :done_put do
		put_ready <= (lock_status * put_requests).pairs(:xid => :xid, :resource => :key) { |s, r| r }

		# Send get request to BasicKVS
		kvput <= put_ready {|p| [:default_client, p.key, p.reqid, p.data] }
		xput_response <= put_ready {|p| [p.xid, p.key, p.reqid] }
		
		# Remove get requests already finished
		put_requests <- put_ready
	end
end