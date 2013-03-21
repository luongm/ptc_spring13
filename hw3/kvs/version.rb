require 'rubygems'
require 'bud'

module MVKVSProtocol
  state do
    interface input, :kvput, [:client, :key] => [:reqid, :value]
    interface input, :kvget, [:reqid] => [:key]
    interface output, :kvget_response, [:reqid, :key] => [:value, :version]
    interface output, :kv_acks, [:reqid]
  end
end

module VersionControlKVS
  include MVKVSProtocol 

  state do
    table :kvstate, [:key, :version] => [:value]
    scratch :r_uninit, kvget.schema
    scratch :r_founds, [:key, :version] => [:reqid, :value]
    scratch :r_found, [:key, :version] => [:reqid, :value]
    scratch :w_uninit, kvput.schema
    scratch :w_found, [:key, :version] => [:reqid, :value]
  end

  bloom :get do
    # if key not in kvstate
    r_uninit <= kvget.notin(kvstate, :key => :key)
    kvget_response <= r_uninit { |u| [u.reqid, u.key, nil, nil] }

    # if key in kvstate
    r_founds <= (kvget * kvstate).pairs(:key => :key) { |g,s| [g.key, s.version, g.reqid, s.value] }
    r_found <= r_founds.argmax([:key], :version) # get the max version
    kvget_response <= r_found { |u| [u.reqid, u.key, u.value, u.version] }
  end

  bloom :put do
    # if key not in kvstate
    w_uninit <= kvput.notin(kvstate, :key => :key)
    kvstate <+ w_uninit { |u| [u.key, 0, u.value] }
    kv_acks <= w_uninit { |u| [u.reqid] }

    # if key in kvstate
    w_found <= (kvput * kvstate).pairs(:key => :key) { |p,s| [p.key, s.version+1, p.reqid, p.value] }
    kvstate <+ w_found { |f| [f.key, f.version, f.value] }
    kv_acks <= w_found { |f| [f.reqid] }
  end
end
