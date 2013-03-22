require 'rubygems'
require 'bud'

module VotingProtocol
  state do
    interface input, :set_requirements, [:request_type] => [:num]
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
    enough_acks <= (counts * requirements).pairs(:request_type => :request_type) { |c,r| [c.reqid, c.key] if c.cnt >= r.num }
  end

  bloom :pass_read_requirements do
    read_result <= (enough_acks * read_acks_received).rights(:reqid => :reqid, :key => :key).argmax([:reqid, :key], :version) do |r|
      [r[1], r[2], r.value] # r = [r.localhost, r.reqid, r.key, r.version, r.value]
    end
    # NOTE: somehow [r.reqid, r.key, r.value] does not work, it returns [r.localhost, r.reqid, r.value] instead
  end

  bloom :pass_write_requirements do
    write_result <+ (enough_acks * write_acks_received).rights(:reqid => :reqid, :key => :key) { |w| [w.reqid] }
  end
end
