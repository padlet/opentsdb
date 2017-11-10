module Opentsdb
  class Client
    attr_reader :host
    attr_reader :port
    attr_accessor :type

    def initialize options = {}
      @faraday = Faraday.new
      self.host = options['host'] || Opentsdb.host
      self.port = options['port'] || Opentsdb.port
      self.type = options['type'] || Opentsdb.type
    end

    def host= host
      @host = host
      @faraday.host = host
    end

    def port= port
      @port = port
      @faraday.port = port
    end

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
      uri = URI.parse url
      uri.query = [@type, uri.query].compact.join('&')

      response = @faraday.send(type, uri.to_s) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = JSON.generate(data) if data
      end

      if !response.success?
        response_content = JSON.parse(response.body) if !response.body.nil? && !response.body.empty?
        error = response_content['error']

        # Error while processing request
        if error
          message = error['details'] || error['message']
          raise ApiError, message, error['trace']

        # Error while creating uid or storing data
        else
          response_content = JSON.parse(response.body) if !response.body.nil? && !response.body.empty?
        end
      else
        response_content = JSON.parse(response.body) if !response.body.nil? && !response.body.empty?
      end

      response_content
    end
  end
end
