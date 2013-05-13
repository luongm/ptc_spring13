require 'webrick'
require 'json'

class BudRESTServer
  def initialize(bud_instance, options={})
    $bud_instance = bud_instance

    if options[:rest_port]
      @server_thread = Thread.new do
        server = WEBrick::HTTPServer.new Port: options[:rest_port]
        server.mount "/", BudServlet
        trap('INT') { server.stop }
        server.start
      end
    end
  end

  class BudServlet < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(request, response)
      response.status = 200
      begin
        action = request.path[1..-1].split("/")[0]
        case action
        when "collections"
          response.body = { tables: non_builtin_collections(Bud::BudTable) }.to_json
        when "rules"
          raise "Unemplemented feature"
        else
          raise "Unrecognized action '#{action}' in path '#{request.path}'"
        end
      rescue Exception => e
        response.body = error_response(e.message)
      end
    end

    def do_POST(request, response)
      response.status = 200
      begin
        action = request.path[1..-1].split("/")[0]
        case action
        when "add_collection"
          handle_request_add_collection(request, response)
        when "add_rows"
          handle_request_add_rows(request, response)
        when "add_rule"
          handle_request_add_rule(request, response)
        else
          raise "Unrecognized action '#{action}' in path '#{request.path}'"
        end
      rescue Exception => e
        response.body = error_response(e.message)
      end
    end

    def do_DELETE(request, response)
      response.status = 200
      begin
        action = request.path[1..-1].split("/")[0]
        case action
        when "remove_rows"
          handle_request_remove_rows(request, response)
        else
          raise "Unrecognized action '#{action}' in path '#{request.path}'"
        end
      rescue Exception => e
        response.body = error_response(e.message, e.backtrace)
      end
    end

    private
    def non_builtin_collections(klass=nil)
      names = $bud_instance.tables.keys - $bud_instance.builtin_tables.keys
      if klass
        names.keep_if do |name|
          $bud_instance.tables[name].class == klass
        end
      end
    end

    private
    def handle_request_add_collection(request, response)
      params = JSON.parse(request.query["params"])
      ['type', 'name', 'keys', 'values'].each do |param|
        raise "Missing required argument: '#{param}'" unless params.include? param
      end

      # parse keys and values columns
      key_cols = params['keys'].map(&:to_sym)
      val_cols = params['values'].map(&:to_sym)

      case params['type']
      when "table"
        $bud_instance.table params['name'].to_sym, key_cols => val_cols
        response.body = { success: "Added table" }.to_json
      when "scratch"
      when "interface"
      when "channel"
      else
        raise "Unrecognized type of collection to add"
      end
    end

    private
    def handle_request_add_rows(request, response)
      params = JSON.parse(request.query["params"])
      ['collection_name', 'op', 'rows'].each do |param|
        raise "Missing required argument: '#{param}'" unless params.include? param
      end
      collection = $bud_instance.tables[params['collection_name'].to_sym]
      raise "Collection '#{params['collection_name']} does not exist!" if collection.nil?

      rows = params['rows']
      case params['op']
      when '<='
        collection <= rows
      when '<+'
        raise "Unemplemented feature"
      when '<~'
        raise "Unemplemented feature"
      else
        raise "Unexpected operation: '#{params['op']}'"
      end
      response.body = { success: "Added rows to collection '#{collection.tabname}'" }.to_json
      # puts "\n[[[[[[[[[[[[here]]]]]]]]]]]]\n\n"
    end

    private
    def handle_request_remove_rows(request, response)
      params = JSON.parse(request.header["data"][0])
      ['collection_name', 'rows'].each do |param|
        raise "Missing required argument: '#{param}'" unless params.include? param
      end
      collection = $bud_instance.tables[params['collection_name'].to_sym]
      raise "Collection '#{params['collection_name']} does not exist!" if collection.nil?

      rows = params['rows']
      collection <- rows
      puts collection.new_delta
      response.body = { success: "Removed rows to collection '#{collection.tabname}'" }.to_json
    end

    private
    def handle_request_add_rule(request, response)
      params = JSON.parse(request.query["params"])
      ['lhs', 'op', 'rhs'].each do |param|
        raise "Missing required argument: '#{param}'" unless params.include? param
      end
      lhs = $bud_instance.tables[params['lhs'].to_sym]
      raise "Collection '#{params['lhs']} does not exist!" if lhs.nil?

      raise "Unemplemented feature"
    end

    private
    def error_response(message, stack_trace=nil)
      error = { errors: message }
      error[:stack_trace] = stack_trace if stack_trace
      return error.to_json
    end
  end
end

