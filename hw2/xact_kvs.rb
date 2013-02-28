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

module TransactionalKVS
	include XactKVSProtocol
	import BasicKVS => :bkvs
	import TwoPhaseLockManager => :lckmgr

	state do
		table :get_requests, [:xid, :key, :reqid]
		table :put_requests, [:xid, :key, :reqid] => [:data]

		scratch :get_ready, [:xid, :key, :reqid]
		scratch :put_ready, [:xid, :key, :reqid] => [:data]

		scratch :lock_status, lckmgr.lock_status.schema
		scratch :kvget_response, bkvs.kvget_response.schema
	end

	bloom :recv_get do
		get_requests <= xget
		lckmgr.request_lock <+ xget {|x| [x.xid, x.key, :S] }
	end

	bloom :recv_put do
		put_requests <= xput
		lckmgr.request_lock <+ xput {|x| [x.xid, x.key, :X] }
	end

	bloom :ready_to_access do
		lock_status <= lckmgr.lock_status
		kvget_response <= bkvs.kvget_response
	end

	bloom :done_get do
		get_ready <= (lock_status * get_requests).pairs(:xid => :xid, :resource => :key) { |s, r| r }

		# Send get request to BasicKVS
		bkvs.kvget <= get_ready {|g| [g.reqid, g.key] }
		xget_response <= (kvget_response * get_requests).pairs(:key => :key, :reqid => :reqid) { |res, req|
			[req.xid, res.key, res.reqid, res.value]
		}

		# end current transactions
		lckmgr.end_xact <+ get_ready {|g| [g.xid] }

		# Remove get requests already finished
		get_requests <- get_ready
	end

	bloom :done_put do
		put_ready <= (lock_status * put_requests).pairs(:xid => :xid, :resource => :key) { |s, r| r }

		# Send get request to BasicKVS
		bkvs.kvput <= put_ready {|p| [:default_client, p.key, p.reqid, p.data] }
		xput_response <= put_ready {|p| [p.xid, p.key, p.reqid] }
		
		# end current transactions
		lckmgr.end_xact <+ put_ready {|p| [p.xid] }

		# Remove get requests already finished
		put_requests <- put_ready
	end
end