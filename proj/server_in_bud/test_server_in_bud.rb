require 'rubygems'
require 'bud'
require 'rest_bud'
require 'test/unit'
require 'rest-client'

class RestBud
  include Bud
end


class TestRestBud < Test::Unit::TestCase
  def get(resource, params=nil)
    RestClient.get "http://localhost:3000/#{resource}", {params: params, :content_type => :json, :accept => :json}
  end

  def post(resource, params=nil)
    RestClient.post "http://localhost:3000/#{resource}", params: params.to_json, :content_type => :json, :accept => :json
  end

  def test_add_collection_and_get_tables
    rest_bud = RestBud.new rest_port: 3000
    rest_bud.run_bg

    # POST /add_collection
    response = post(:add_collection, {type: "table", name: "test_table", keys: ["k1","k2"], values: ["v1","v2"]})
    assert_equal(response.code, 200)

    data = JSON.parse(response.strip)
    assert(data.include?("success"), "Did not receive success message when adding table\n #{data.inspect}")
    assert(rest_bud.tables.include?(:test_table), "Bud instance should include the added table's name")
    key_cols = rest_bud.tables[:test_table].key_cols
    val_cols = rest_bud.tables[:test_table].cols - key_cols
    assert_equal(key_cols, [:k1, :k2])
    assert_equal(val_cols, [:v1, :v2])

    # GET /tables
    response = get(:tables)
    assert_equal(response.code, 200)
    
    data = JSON.parse(response.strip)
    assert(data.include?("tables"), "Did not receive success message when adding table")
    assert_equal(data["tables"], ["test_table"])
  end
end

