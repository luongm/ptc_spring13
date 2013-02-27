module LockMgrProtocol
	state do
		interface input, :request_lock, [:xid, :resource] => [:mode]
		interface input, :end_xact, [:xid]
		interface output, :lock_status, [:xid, :resource] => [:status]
	end
end

module LockManager
	include LockMgrProtocol

	state do
		table :waiting_locks, [:xid, :resource] => [:mode]
		table :granted_locks, [:xid, :resource] => [:mode]

		scratch :read_locks, [:xid, :resource] => [:mode]
		scratch :write_locks, [:xid, :resource] => [:mode]

		scratch :group_queue, [:resource] => [:xid]
		scratch :group_queue_single, [:xid, :resource, :mode]

		scratch :read_candidates, [:xid, :resource] => [:mode]
		scratch :write_candidates, [:xid, :resource] => [:mode]

		scratch :can_read, [:xid, :resource] => [:mode]
		scratch :can_write, [:xid, :resource] => [:mode]
	end

	bloom :set_up do
		read_locks  <= granted_locks {|l| l if l.mode == :S }
		write_locks <= granted_locks {|l| l if l.mode == :X }
	end

	bloom :receive_new_requests do
		waiting_locks <= request_lock

		group_queue <= waiting_locks.group([:resource], choose(:xid))
		group_queue_single <= (group_queue * waiting_locks).rights(:resource => :resource, :xid => :xid)
	end

	bloom :grant_read_locks do
		# Add any requests that are waiting but not in success lock
		read_candidates <= group_queue_single {|l| l if l.mode == :S}
		can_read <= read_candidates.notin(write_locks, :resource => :resource)

		# save read locks as acquired
		# read_locks <+ can_read
		granted_locks <+ can_read

		# output
		lock_status <= can_read { |r| [r.xid, r.resource, :OK] }

		# remove granted read locks from waiting_locks
		waiting_locks <- can_read
	end

	bloom :grant_write_locks do
		# Add any requests that are waiting but not in success lock
		write_candidates <= group_queue_single {|l| l if l.mode == :X}
		can_write <= write_candidates.notin(granted_locks, :resource => :resource)

		# save write locks as acquired
		# write_locks <+ can_write
		granted_locks <+ can_write

		# output
		lock_status <= can_write { |r| [r.xid, r.resource, :OK] }

		# remove granted write locks from waiting_locks
		waiting_locks <- can_write
	end

	bloom :end_xact_free_resources do
		# remove from waiting list and all tables that store acquired locks
		waiting_locks <- (waiting_locks * end_xact).lefts(:xid => :xid)
		granted_locks <- (granted_locks * end_xact).lefts(:xid => :xid)
		# read_locks <- (read_locks * end_xact).lefts(:xid => :xid)
		# write_locks <- (write_locks * end_xact).lefts(:xid => :xid)
	end
end