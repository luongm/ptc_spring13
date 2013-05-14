gem 'ruby_parser', '>= 3.0.2'
require 'ruby_parser'
require 'webrick'
require 'json'

class BudRESTServer
  def initialize(klass, bud_instance, options={})
    $bud_class = RestBud
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
      parse_header_params request
      begin
        action = request.path[1..-1].split("/")[0]
        case action
        when "collections"
          get_collections(request)
        when "content"
          get_content(request)
        when "rules"
          get_rules(request)
        else
          raise "Unrecognized action '#{action}' in path '#{request.path}'"
        end
        response.body = @response.to_json
      rescue Exception => e
        response.body = error_response(e.message)
      end
    end

    def do_POST(request, response)
      response.status = 200
      parse_query_params request
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
      parse_header_params request
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
    def get_collections(request)
      names = $bud_instance.tables.keys - $bud_instance.builtin_tables.keys
      collections = {}
      {
        :tables => Bud::BudTable,
        :scratches => Bud::BudScratch,
        :input_interfaces => Bud::BudInputInterface,
        :output_interfaces => Bud::BudOutputInterface,
        :channels => Bud::BudChannel
      }.each do |sym, klass|
        results = names.select { |name| name if $bud_instance.tables[name].class == klass }
        collections[sym] = results unless results.empty?
      end
      @response = { collections: collections }
    end

    def get_content(request)
      require_param_keys ['collection_name']
      collection_name = @params['collection_name']
      collection = $bud_instance.tables[collection_name.to_sym]
      raise "Collection '#{collection_name} does not exist!" if collection.nil?
      @response = { content: collection.to_a.map(&:to_a) }
    end

    def get_rules(request)
      @response = { rules: $bud_instance.t_rules.to_a.map {|x| x[5]} }
    end

    def handle_request_add_collection(request, response)
      ['type', 'collection_name', 'keys', 'values'].each do |param|
        raise "Missing required argument: '#{param}'" unless @params.include? param
      end

      # parse keys and values columns
      key_cols = @params['keys'].map(&:to_sym)
      val_cols = @params['values'].map(&:to_sym)
      collection_name = @params['collection_name']

      case @params['type']
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

    def handle_request_add_rows(request, response)
      ['collection_name', 'op', 'rows'].each do |param|
        raise "Missing required argument: '#{param}'" unless @params.include? param
      end
      collection = $bud_instance.tables[@params['collection_name'].to_sym]
      raise "Collection '#{@params['collection_name']} does not exist!" if collection.nil?

      rows = @params['rows']
      case @params['op']
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
        raise "Unexpected operation: '#{@params['op']}'"
      end
      response.body = { success: "Added rows to collection '#{collection.tabname}'" }.to_json
    end

    def handle_request_remove_rows(request, response)
      ['collection_name', 'rows'].each do |param|
        raise "Missing required argument: '#{param}'" unless @params.include? param
      end
      collection = $bud_instance.tables[@params['collection_name'].to_sym]
      raise "Collection '#{@params['collection_name']} does not exist!" if collection.nil?

      rows = @params['rows']
      collection <- rows
      collection.tick
      response.body = { success: "Removed rows from collection '#{collection.tabname}'" }.to_json
    end

    def handle_request_add_rule(request, response)
      ['lhs', 'op', 'rhs'].each do |param|
        raise "Missing required argument: '#{param}'" unless @params.include? param
      end

      rule = "#{@params['lhs']} #{@params['op']} #{@params['rhs']}"
      $bud_class.add_rule(rule)
      $bud_instance.reload
      response.body = { success: "Added rule to bud" }.to_json
    end

    def error_response(message, backtrace=nil)
      error = { errors: message }
      error[:stack_trace] = backtrace if backtrace
      return error.to_json
    end

    def parse_header_params(request)
      @params = JSON.parse(request.header["params"][0])
    end

    def parse_query_params(request)
      @params = JSON.parse(request.query["params"])
    end

    def require_param_keys(keys)
      keys.each do |param|
        raise "Missing required argument: '#{param}'" unless @params.include? param
      end
    end
  end
end
