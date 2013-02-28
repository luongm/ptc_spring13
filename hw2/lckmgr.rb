module LockMgrProtocol
	state do
		interface input, :request_lock, [:xid, :resource] => [:mode]
		interface input, :end_xact, [:xid]
		interface output, :lock_status, [:xid, :resource] => [:status]
	end
end

module TwoPhaseLockMgr
	include LockMgrProtocol

	state do
		table :waiting_locks, [:xid, :resource, :mode] => [:time]
		table :granted_locks, [:xid, :resource] => [:mode, :time]

		scratch :read_locks, [:xid, :resource] => [:mode, :time]
		scratch :write_locks, [:xid, :resource] => [:mode, :time]

		scratch :group_queue, [:xid, :resource, :mode, :time]
		scratch :group_queue_single, [:xid, :resource, :mode, :time]

		scratch :read_candidates, [:xid, :resource] => [:mode, :time]
		scratch :write_candidates, [:xid, :resource] => [:mode, :time]

		scratch :can_ignore, [:xid, :resource] => [:mode, :time]

		scratch :upgradable, [:xid, :resource] => [:mode, :time]
		scratch :same_resource, [:xid, :resource] => [:mode, :time]
		scratch :can_upgrade, [:xid, :resource] => [:mode, :time]

		scratch :can_read, [:xid, :resource] => [:mode, :time]
		scratch :can_write, [:xid, :resource] => [:mode, :time]
	end

	bloom :set_up do
		read_locks  <= granted_locks {|l| l if l.mode == :S }
		write_locks <= granted_locks {|l| l if l.mode == :X }
	end

	bloom :receive_new_requests do
		waiting_locks <= request_lock {|l| [l.xid, l.resource, l.mode, budtime] }

		group_queue <= waiting_locks.argmin([:resource], :time)
		group_queue_single <= group_queue.argagg(:choose, [:resource], :xid)
	end

	bloom :ignore_new_read_requests_if_write_locks_existed do
		can_ignore <= (waiting_locks * write_locks).pairs(:xid => :xid, :resource => :resource) do |wait, write|
			wait if wait.mode == :S
		end

		# output
		lock_status <= can_ignore { |u| [u.xid, u.resource, :OK] }

		# remove the write lock from waiting_locks
		waiting_locks <- can_ignore
	end

	bloom :upgrade_read_lock_to_write_lock do
		upgradable <= (waiting_locks * read_locks).pairs(:xid => :xid, :resource => :resource) do |w, r|
			w if w.mode == :X
		end
		same_resource <= (upgradable * read_locks).pairs(:resource => :resource) do |u, r|
			r if u.xid != r.xid
		end
		can_upgrade <= (upgradable * same_resource).outer(:xid => :xid) do |u, s|
			u if same_resource.length == 0
		end

		# upgrade the granted lock and remove the waiting one
		granted_locks <+- can_upgrade
		waiting_locks <- can_upgrade
	end

	bloom :grant_read_locks do
		# Add any requests that are waiting but not in success lock
		read_candidates <= group_queue_single {|l| l if l.mode == :S}
		can_read <= read_candidates.notin(write_locks, :resource => :resource)

		# save read locks as acquired
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
	end
end