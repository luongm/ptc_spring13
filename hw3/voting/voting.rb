require 'rubygems'
require 'bud'

module VotingProtocol
  state do
    interface input, :set_requirements, [] => [:r_fraction, :w_fraction]
    interface input, :read_ack, [:from, :reqid, :key] => [:version, :value]
    interface input, :write_ack, [:from, :reqid, :key] => []

    interface output, :read_result, [:reqid, :key] => [:value]
    interface output, :write_result, [:reqid] => []
  end
end

module VoteCounter
  include VotingProtocol

  state do
    table :requirements, set_requirements.schema
    table :read_acks_received, [:from, :reqid, :key] => [:version, :value]
    table :write_acks_received, [:from, :reqid, :key] => []
    table :done_read, [:reqid, :key]
    table :done_write, [:reqid]

    scratch :not_done_read, read_acks_received.schema
    scratch :not_done_write, write_acks_received.schema

    scratch :counts, [:request_type, :reqid, :key] => [:cnt]

    scratch :enough_acks, [:reqid, :key] => []
  end

  bloom :setup do
    requirements <= set_requirements
  end

  bloom :recv_acks_from_nodes do
    read_acks_received <= read_ack
    write_acks_received <= write_ack

    counts <= read_acks_received.group([:reqid, :key], count()) { |r| [:read] + r }
    counts <= write_acks_received.group([:reqid, :key], count()) { |w| [:write] + w }
  end

  bloom :get_high_enough_counts do
    # also get the value that have the highest version number
    enough_acks <= (counts * requirements).pairs do |c,r|
      [c.reqid, c.key] if (c.request_type == :read and c.cnt >= r.r_fraction) or (c.request_type == :write and c.cnt >= r.w_fraction)
    end
  end

  bloom :pass_read_requirements do
    not_done_read <= read_acks_received.notin(done_read, :reqid => :reqid, :key => :key)
    read_result <+ (enough_acks * not_done_read).rights(:reqid => :reqid, :key => :key).argmax([:reqid, :key], :version) do |r|
      [r[1], r[2], r.value] # r = [r.localhost, r.reqid, r.key, r.version, r.value]
    end
    done_read <= read_result { |r| [r.reqid, r.key] }
    # NOTE: somehow [r.reqid, r.key, r.value] does not work, it returns [r.localhost, r.reqid, r.value] instead
  end

  bloom :pass_write_requirements do
    not_done_write <= write_acks_received.notin(done_write, :reqid => :reqid)
    write_result <+ (enough_acks * not_done_write).rights(:reqid => :reqid) { |w| [w.reqid] }
    done_write <= write_result { |w| [w.reqid] }
  end
end
