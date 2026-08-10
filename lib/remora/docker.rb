module Remora
  # Thin client for the Docker Engine API over the local unix socket.
  class Docker
    class Error < StandardError; end

    DEFAULT_SOCKET = "/var/run/docker.sock".freeze

    def initialize(socket: ENV.fetch("DOCKER_SOCKET", DEFAULT_SOCKET))
      @socket = socket
    end

    def version
      get("/version")
    end

    def containers(all: true)
      get("/containers/json", query: { all: all })
    end

    def inspect_container(id)
      get("/containers/#{id}/json")
    end

    private

    def get(path, query: {})
      response = connection.request(method: :get, path: path, query: query)
      raise Error, engine_message(response) if response.status >= 400

      JSON.parse(response.body)
    rescue Excon::Error => e
      raise Error, "Docker socket #{@socket}: #{e.message}"
    end

    def connection
      @connection ||= Excon.new("unix:///", socket: @socket, persistent: true)
    end

    def engine_message(response)
      JSON.parse(response.body).fetch("message")
    rescue JSON::ParserError, KeyError
      "Docker Engine returned #{response.status}"
    end
  end
end
