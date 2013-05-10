require 'rest-client'
require 'json'
require 'minitest/autorun'

class TestExam1 < MiniTest::Unit::TestCase
  def get(resource, params=nil)
    RestClient.get("http://localhost:3000/#{resource}", {:params => params})
  end

  def post(resource, params=nil)
    RestClient.post("http://localhost:3000/#{resource}", params)
  end
  
  def setup
    post(:reset)
  end

  def test_add_collection
    response = post(:add_collection, {type: "table", name: "test_table", keys: ["k1","k2"], values: ["v1","v2"]})
    assert_equal(response.code, 200)

    data = JSON.parse(response.strip)
    assert(data.include?("success"), "Did not receive success message when adding table")
  end

  def test_get_tables
    post(:add_collection, {type: "table", name: "test_table", keys: ["k1","k2"], values: ["v1","v2"]})
    response = get(:tables)
    assert_equal(response.code, 200)
    
    data = JSON.parse(response.strip)
    assert(data.include?("tables"), "Did not receive success message when adding table")
    assert_equal(data["tables"], ["test_table"])
  end
end

