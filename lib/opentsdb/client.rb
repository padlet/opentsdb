module Opentsdb
  class Client
    attr_reader :host
    attr_reader :port
    attr_accessor :type
    attr_accessor :timezone
    attr_accessor :logger

    # Create a new client instance
    #
    # @param [Hash] options
    # @option options [String] :host ("127.0.0.1") server hostname
    # @option options [Fixnum] :port (4242) server port
    # @option options [String] :type (details) response type for queries
    # @option options [String] :timezone (UTC) timezone used in queries
    # @option options [Logger] :logger (nil) logger
    #
    # @return Opentsdb::Client
    def initialize options = {}
      @faraday = Faraday.new do |conn|
        conn.adapter :httpclient
      end
      self.host = options[:host] || Opentsdb.host
      self.port = options[:port] || Opentsdb.port
      self.type = options[:type] || Opentsdb.type
      self.timezone = options[:timezone] || Opentsdb.timezone
      self.logger = options[:logger] || Opentsdb.logger
    end

    def host= host
      @host = host
      @faraday.host = host
    end

    def port= port
      @port = port
      @faraday.port = port
    end

    # Drop database caches
    def drop_caches
      request '/api/dropcaches', :get
    end

    # Create uid or multiple uids
    def assign_uid uid
      request '/api/uid/assign', :post, uid
    end

    # Create single data point or multiple data points
    def put data
      if !data.is_a?(Hash) && !data.is_a?(Array)
        raise ArgumentError, 'Argument should be a Hash or an Array'
      end

      request '/api/put', :post, data
    end

    # Query data points
    def query query
      request '/api/query', :post, query
    end

    # Delete data points
    def delete query
      request '/api/query', :delete, query
    end

    # Query data points using expression
    def exp query
      request '/api/query/exp', :post, query
    end

    # Query latest value of time series
    def last query
      request '/api/query/last', :post, query
    end

    # Get suggestions from database by query and type
    def suggest query, type = 'metrics', max = nil
      request = {
        type: type,
        q: query
      }
      request[:max] = max unless max.nil?

      request '/api/suggest', :post, request
    end

  private
    # Send request to REST interface of database
    def request url, type = :get, data = nil
      query_parameters = [@type, "tz=#{self.timezone}"]
      uri = URI.parse url
      uri.query = [query_parameters, uri.query].compact.join('&')
      error = nil
      start_time = Time.now

      response = @faraday.send(type, uri.to_s) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = JSON.generate(data) if data
      end
      finish_time = Time.now
      method_name = caller[0][/`.*'/][1..-2]
      unless logger.nil?
        duration = (finish_time - start_time).in_milliseconds
        duration = BigDecimal.new(duration, 3)
        logger.debug(:opentsdb) {"(#{duration}ms) method: #{method_name} data: #{data}"}
      end

      begin
        response_content = JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        response_content = {}
      end

      unless response.success?
        # Regular error
        if response_content.has_key?("error")
          error = response_content['error']
          message = error['details'] || error['message']
          matches = message.match(/No such name for '([^']+)':\s+'([^']+)'/)

          # Got an error about not existing UID
          unless matches.nil? || matches.captures.empty?
            uid_type = matches[1].singularize.camelize
            exception_class = "Opentsdb::#{uid_type}NotExistsError".constantize
            raise exception_class, message, error['trace']
          end

          raise ApiError, message, error['trace']
        end
      end

      response_content
    end
  end
end
