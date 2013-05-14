gem 'ruby_parser', '>= 3.0.2'
require 'ruby_parser'
require 'webrick'
require 'json'

class BudRESTServer
  def initialize(bud_instance, options={})
    $bud_instance = bud_instance
    $rule_num = 0

    if options[:rest_port]
      @server_thread = Thread.new do
        @server = WEBrick::HTTPServer.new Port: options[:rest_port]
        @server.mount "/", BudServlet
        trap('INT') { @server.stop }
        @server.start
      end
    end
  end

  def stop
    @server.stop
  end

  class BudServlet < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(request, response)
      response.status = 200
      begin
        action = request.path[1..-1].split("/")[0]
        case action
        when "collections"
          handle_request_get_collections(request, response)
        when "content"
          handle_request_get_content(request, response)
        when "rules"
          # TODO
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
        response.body = error_response(e.message)
      end
    end

    private
    def handle_request_get_collections(request, response)
      names = $bud_instance.tables.keys - $bud_instance.builtin_tables.keys
      collections = {
        tables: names.select { |name| name if $bud_instance.tables[name].class == Bud::BudTable },
        scratches: names.select { |name| name if $bud_instance.tables[name].class == Bud::BudScratch },
        input_interfaces: names.select { |name| name if $bud_instance.tables[name].class == Bud::BudInputInterface },
        output_interfaces: names.select { |name| name if $bud_instance.tables[name].class == Bud::BudOutputInterface },
        channels: names.select { |name| name if $bud_instance.tables[name].class == Bud::BudChannel }
      }
      collections.delete_if { |k,v| v.empty? }
      response.body = { collections: collections }.to_json
    end

    private
    def handle_request_get_content(request, response)
      params = JSON.parse(request.header["data"][0])
      ['collection_name'].each do |param|
        raise "Missing required argument: '#{param}'" unless params.include? param
      end
      collection = $bud_instance.tables[params['collection_name'].to_sym]
      raise "Collection '#{params['collection_name']} does not exist!" if collection.nil?

      content = []
      collection.each do |row|
        content << row.to_a
      end
      response.body = { content: content }.to_json
    end

    private
    def handle_request_add_collection(request, response)
      params = JSON.parse(request.query["params"])
      ['type', 'collection_name', 'keys', 'values'].each do |param|
        raise "Missing required argument: '#{param}'" unless params.include? param
      end

      # parse keys and values columns
      key_cols = params['keys'].map(&:to_sym)
      val_cols = params['values'].map(&:to_sym)
      collection_name = params['collection_name']

      case params['type']
      when "table"
        $bud_instance.table collection_name.to_sym, key_cols => val_cols
        response.body = { success: "Added table '#{collection_name}'" }.to_json
      when "scratch"
        $bud_instance.scratch collection_name.to_sym, key_cols => val_cols
        response.body = { success: "Added scratch '#{collection_name}'" }.to_json
      when "input_interface"
        $bud_instance.interface true, collection_name.to_sym, key_cols => val_cols
        response.body = { success: "Added input interface '#{collection_name}'" }.to_json
      when "output_interface"
        $bud_instance.interface false, collection_name.to_sym, key_cols => val_cols
        response.body = { success: "Added output interface '#{collection_name}'" }.to_json
      when "channel"
        $bud_instance.channel collection_name.to_sym, key_cols => val_cols
        response.body = { success: "Added channel '#{collection_name}'" }.to_json
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
        collection.flush_deltas
      when '<+'
        # TODO
        raise "Unemplemented feature"
      when '<~'
        # TODO
        raise "Unemplemented feature"
      else
        raise "Unexpected operation: '#{params['op']}'"
      end
      response.body = { success: "Added rows to collection '#{collection.tabname}'" }.to_json
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
      collection.tick
      response.body = { success: "Removed rows to collection '#{collection.tabname}'" }.to_json
    end

    private
    def handle_request_add_rule(request, response)
      # TODO
      params = JSON.parse(request.query["params"])
      ['lhs', 'op', 'rhs'].each do |param|
        raise "Missing required argument: '#{param}'" unless params.include? param
      end
      lhs = $bud_instance.tables[params['lhs'].to_sym]
      raise "Collection '#{params['lhs']} does not exist!" if lhs.nil?

      parser = RubyParser.for_current_ruby
      rule = "#{params['lhs']} #{params['op']} #{params['rhs']}"
      ast = parser.parse rule

      raise "Unemplemented feature"
    end

    private
    def error_response(message, backtrace=nil)
      error = { errors: message }
      error[:stack_trace] = backtrace if backtrace
      return error.to_json
    end
  end
end

