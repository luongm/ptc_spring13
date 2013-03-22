require 'rubygems'
require 'bud'
require 'membership/membership'
require 'kvs/quorum_kvsproto'
require 'kvs/version'
require 'voting/voting'

module QuorumKVS
  include StaticMembership
  include QuorumKVSProtocol
  import VersionControlKVS => :vkvs
  import VoteCounter => :votebox

  state do
    table   :qconfig, [] => [:r_fraction, :w_fraction]
    channel :kvput_chan, [:@dest, :from, :client, :key] => [:reqid, :value]
    channel :kvget_chan, [:@dest, :from, :reqid] => [:key]
    channel :kvget_response_chan, [:@dest, :reqid] => [:key, :value, :version]
    channel :kv_acks_chan, [:@dest, :reqid, :key]

    table :kvput_queue, [:dest, :from, :client] => [:key, :reqid, :value]
    table :kvget_queue, [:dest, :from, :reqid] => [:key]
  end

  bloom :config do
    qconfig <+ quorum_config { |q| q unless qconfig.exists? }
    votebox.set_requirements <= qconfig do |c|
      r = (c.r_fraction*member.length).ceil
      w = (c.w_fraction*member.length).ceil
      [r == 0 ? 1 : r, w == 0 ? 1 : w]
    end
  end

  bloom :broadcast do
    kvput_chan <~ (member * kvput).pairs { |m,k| [m.host, ip_port] + k.to_a}
    kvget_chan <~ (member * kvget).pairs { |m,k| [m.host, ip_port] + k.to_a}
  end

  bloom :receive_requests do
    kvput_queue <= kvput_chan
    kvget_queue <= kvget_chan

    vkvs.kvput <= kvput_chan { |k| k.to_a.drop(2) }
    vkvs.kvget <= kvget_chan { |k| k.to_a.drop(2) }

    # kv_acks_chan <~ kvput_chan { |k| [k.from, k.reqid, k.key] }
    kvget_response_chan <~ (kvget_queue * vkvs.kvget_response).pairs(:reqid => :reqid) do |c,r|
      [c.from] + r.to_a
    end
    kv_acks_chan <~ (kvput_queue * vkvs.kv_acks).pairs(:reqid => :reqid) do |p,a|
      [p.dest, p.reqid, p.key]
    end

    kvget_queue <- (kvget_queue * vkvs.kvget_response).lefts(:reqid => :reqid)
    kvput_queue <- (kvput_queue * vkvs.kv_acks).lefts(:reqid => :reqid)

    votebox.read_ack <= kvget_response_chan { |g| [g.dest, g.reqid, g.key, g.version, g.value] }
    votebox.write_ack <= kv_acks_chan { |a| [a.dest, a.reqid, a.key] }
  end

  bloom :responses do
    kvget_response <= votebox.read_result
    kv_acks <= votebox.write_result
  end
end
