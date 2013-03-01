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
	import BasicKVS => :kvs
	import TwoPhaseLockMgr => :lckmgr

	state do
		interface input, :end_xact, [:xid]

		table :get_requests, [:xid, :key, :reqid]
		table :put_requests, [:xid, :key, :reqid] => [:data]

		scratch :get_ready, [:xid, :key, :reqid]
		scratch :put_ready, [:xid, :key, :reqid] => [:data]

		scratch :lock_status, [:xid, :resource] => [:status]
		scratch :kvget_response, [:reqid] => [:key, :value]
 	end

	bloom :setting_up do
		lock_status <= lckmgr.lock_status
		kvget_response <= kvs.kvget_response
	end

	bloom :recv_get do
		get_requests <= xget
		lckmgr.request_lock <+ xget {|x| [x.xid, x.key, :S] }
	end

	bloom :recv_put do
		put_requests <= xput
		lckmgr.request_lock <+ xput {|x| [x.xid, x.key, :X] }
	end

	bloom :done_get do
		get_ready <= (lock_status * get_requests).pairs(:xid => :xid, :resource => :key) { |s, r| r }#if s[0] == r[0] and s[1] == r[1] }

		# Send get request to BasicKVS
		kvs.kvget <= get_ready {|g| [g.reqid, g.key] }
		xget_response <= (kvget_response * get_requests).pairs(:key => :key, :reqid => :reqid) { |res, req|
			[req.xid, res.key, res.reqid, res.value]
		}

		# Remove get requests already finished
		get_requests <- get_ready
	end

	bloom :done_put do
		put_ready <= (lock_status * put_requests).pairs(:xid => :xid, :resource => :key) { |s, r| r }#if s[0] == r[0] and s[1] == r[1] }

		# Send get request to BasicKVS
		kvs.kvput <= put_ready {|p| [:default_client, p.key, p.reqid, p.data] }
		xput_response <= put_ready {|p| [p.xid, p.key, p.reqid] }
		
		# Remove get requests already finished
		put_requests <- put_ready
	end

	bloom :end_xacts do
		lckmgr.end_xact <= end_xact
	end
end