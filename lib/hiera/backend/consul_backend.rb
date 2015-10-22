require 'net/http'
require 'net/https'
require 'json'
require 'base64'

class ConfigurationError < ArgumentError
end

# Hiera backend for Consul
class Hiera
  module Backend
    class Consul_backend
      @api_version = 'v1'

      class << self
        attr_reader :api_version
      end

      attr_reader :host, :consul

      def initialize
        begin
          @config = Config[:consul]
        rescue StandardError => e
          raise ConfigurationError, "[hiera-consul]: config cannot be read: #{e}"
        end

        verify_config!
        parse_hosts!

        @consul = setup_consul
        use_ssl!

        @cache = {}
        build_cache!
      end

      def lookup(key, scope, order_override, _resolution_type)
        answer = nil

        paths = resolve_paths(key, scope, order_override)
        paths.unshift(order_override) if order_override

        filtered_paths = filter_paths(paths, key)

        filtered_paths.each do |path|
          return @cache[key] if path == 'services' && @cache.key?(key)

          debug("Lookup #{path}/#{key} on #{@host}:#{@config[:port]}")

          answer = wrapquery("#{path}/#{key}")
          break if answer
        end

        answer
      end

      def resolve_paths(key, scope, order_override)
        if @config[:base]
          Backend.datasources(scope, order_override) do |source|
            url = "#{@config[:base]}/#{source}"
            Backend.parse_string(url, scope, 'key' => key)
          end
        elsif @config[:paths]
          @config[:paths].map { |p| Backend.parse_string(p, scope, 'key' => key) }
        else
          probable_source = @config[:base] ? :base : :paths
          raise ConfigurationError, "[hiera-consul]: There is an issue with your hierarchy. Please check #{probable_source} configuration"
          exit 1
        end
      end

      def verify_config!
        return true if
          @config[:host] && @config[:port] && (@config[:paths] || @config[:base])
        raise ConfigurationError, '[hiera-consul]: Missing minimum configuration, please check hiera.yaml'
      end

      def parse_hosts!
        @hosts =
          if @config[:host].is_a?(String)
            [@config[:host]]
          else
            @config[:host]
          end
      end

      def setup_consul
        fail '[hiera-consul]: No consul server is available' if @hosts.empty?
        @host = @hosts.shift

        debug "Trying #{@host}"
        @consul              = Net::HTTP.new(@host, @config[:port])
        @consul.read_timeout = @config[:http_read_timeout] || 10
        @consul.open_timeout = @config[:http_connect_timeout] || 10
        @consul
      end

      def consul_fallback
        debug "Could not reach #{@host}, retrying with #{@hosts.first}"
        setup_consul
      end

      def use_ssl!
        if @config[:use_ssl]
          @consul.use_ssl = true
          config_ssl!
        else
          @consul.use_ssl = false
        end
      end

      def config_ssl!
        msg = '[hiera-consul]: use_ssl is enabled but no ssl_cert is set'
        fail msg unless @config[:ssl_cert]

        ssl_verify!
        ssl_store!
        ssl_key!
        ssl_cert!
      end

      def ssl_verify!
        if @config[:ssl_verify]
          @consul.verify_mode = OpenSSL::SSL::VERIFY_PEER
        else
          @consul.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
      end

      def store
        return @store if @store
        ssl_store!
        @store
      end

      def ssl_store!
        @store = OpenSSL::X509::Store.new
        @store.add_cert(OpenSSL::X509::Certificate.new(File.read(@config[:ssl_ca_cert])))
        @consul.cert_store = @store
      end

      def ssl_key!
        debug("ssl_key: #{File.expand_path(@config[:ssl_key])}")
        @consul.key = OpenSSL::PKey::RSA.new(File.read(@config[:ssl_key]))
      end

      def ssl_cert!
        debug("ssl_cert: #{File.expand_path(@config[:ssl_cert])}")
        @consul.cert = OpenSSL::X509::Certificate.new(File.read(@config[:ssl_cert]))
      end

      def filter_paths(paths, key)
        paths.reduce([]) do |acc, path|
          if "#{path}/#{key}".match('//')
            # Check that we are not looking somewhere that will make hiera
            # crash subsequent lookups
            debug("The specified path #{path}/#{key} is malformed, skipping")
          elsif path !~ %r{^/v\d/(catalog|kv)/}
            # We only support querying the catalog or the kv store
            debug("We only support queries to catalog and kv and you asked #{path}, skipping")
          else
            acc << path
          end
          acc
        end
      end

      def parse_result(res)
        # Consul always returns an array
        res_array = JSON.parse(res)

        # See if we are a k/v return or a catalog return
        unless res_array.length > 0
          debug('Jumped as array empty')
          return nil
        end

        if res_array.first.include? 'Value'
          Base64.decode64(res_array.first['Value'])
        else
          res_array
        end
      end

      def wrapquery(path)
        httpreq = Net::HTTP::Get.new("#{path}#{token(path)}")
        result  = request(httpreq)

        if result.nil?
          debug('No response from any server')
          return nil
        end

        unless result.is_a?(Net::HTTPSuccess)
          debug("HTTP response code was #{result.code}")
          return nil
        end

        if result.body == 'null'
          debug('Jumped as consul null is not valid')
          return nil
        end

        debug("Answer was #{result.body}")
        parse_result(result.body)
      end

      # Token is passed only when querying kv store
      def token(path)
        "?token=#{@config[:token]}" if @config[:token] && path =~ %r{^/v\d/kv/}
      end

      def request(httpreq)
        @consul.request(httpreq)
      rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError, Errno::ECONNREFUSED => e
        if @hosts.length >= 1
          consul_fallback
          retry
        else
          debug('Could not connect to Consul')
          raise Exception, e.message unless @config[:failure] == 'graceful'
          return nil
        end
      end

      def query_services
        path = "/#{self.class.api_version}/catalog/services"
        debug("Querying #{@host}#{path}")
        wrapquery(path)
      end

      def query_service(key)
        path = "/#{self.class.api_version}/catalog/service/#{key}"
        debug("Querying #{path}")
        wrapquery(path)
      end

      def build_cache!
        services = query_services
        return nil unless services.is_a? Hash

        services.each do |key, _|
          cache_service(key)
        end

        debug("Cache: #{@cache}")
      end

      def cache_service(key)
        service = query_service(key)
        return nil unless service.is_a?(Array)

        service.each do |node_hash|
          node = node_hash['Node']
          cache_node(key, node, node_hash)
        end
      end

      # Store the value of a particular node
      def cache_node(key, node, node_hash)
        node_hash.each do |property, value|
          next if property == 'ServiceID'

          update_cache(key, value, property, node)
        end
      end

      def update_cache(key, value, property, node)
        @cache["#{key}_#{property}_#{node}"] = value unless property == 'Node'

        if @cache.key?("#{key}_#{property}")
          @cache["#{key}_#{property}_array"].push(value)
        else
          # Value of the first registered node
          @cache["#{key}_#{property}"] = value

          # Values of all nodes
          @cache["#{key}_#{property}_array"] = [value]
        end
      end

      private

      def debug(msg)
        Hiera.debug("[hiera-consul]: #{msg}")
      end
    end
  end
end
