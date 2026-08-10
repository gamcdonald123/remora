module Remora
  # Thin client for the Docker Engine API over the local unix socket.
  class Docker
    class Error < StandardError; end
    # Raised on read timeouts during follow streams — callers ping the client
    # (proving it's still there) and resume from the last seen timestamp.
    class TimeoutError < Error; end

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

    # Blocks, yielding each event as a parsed hash until the stream ends.
    # Events arrive as newline-delimited JSON in arbitrary chunk sizes.
    def events(since: nil, &block)
      buffer = +""
      streamer = lambda do |chunk, _remaining, _total|
        buffer << chunk
        while (line = buffer.slice!(/.*\n/))
          block.call(JSON.parse(line))
        end
      end

      connection.request(
        method: :get, path: "/events",
        query: { since: since }.compact,
        response_block: streamer,
        read_timeout: 3600
      )
      true
    rescue Excon::Error => e
      raise Error, "Docker socket #{@socket}: #{e.message}"
    end

    # Merged stdout+stderr tail as one UTF-8 string, demuxed when the
    # container has no TTY.
    def logs(id, tail: 500, timestamps: false)
      tty = inspect_container(id).dig("Config", "Tty")
      body = request(
        :get, "/containers/#{id}/logs",
        query: { stdout: 1, stderr: 1, tail: tail, timestamps: timestamps ? 1 : 0 }
      ).body
      raw = tty ? body.dup : LogDemux.call(body)
      raw.force_encoding(Encoding::UTF_8).scrub
    ensure
      @connection&.reset
    end

    # Follows the log stream, yielding demuxed text as it arrives. Always
    # requests engine timestamps so callers can track a resume position.
    def stream_logs(id, since:, read_timeout: 15, &block)
      tty = inspect_container(id).dig("Config", "Tty")
      demuxer = tty ? nil : LogDemux::Streamer.new
      streamer = lambda do |chunk, _remaining, _total|
        text = demuxer ? demuxer.push(chunk) : chunk
        block.call(text) unless text.empty?
      end

      connection.request(
        method: :get, path: "/containers/#{id}/logs",
        query: { follow: 1, stdout: 1, stderr: 1, tail: 0, timestamps: 1, since: since },
        response_block: streamer,
        read_timeout: read_timeout
      )
      true
    rescue Excon::Errors::Timeout => e
      raise TimeoutError, e.message
    rescue Excon::Error => e
      raise Error, "Docker socket #{@socket}: #{e.message}"
    end

    # Runs a command in the container, returning demuxed combined output.
    def exec(id, cmd)
      created = JSON.parse(
        request(:post, "/containers/#{id}/exec",
                body: { AttachStdout: true, AttachStderr: true, Cmd: cmd }.to_json).body
      )
      response = request(:post, "/exec/#{created.fetch("Id")}/start",
                         body: { Detach: false, Tty: false }.to_json)
      LogDemux.call(response.body)
    ensure
      # The exec stream has no content length — the persistent connection
      # can't be trusted for another request afterwards.
      @connection&.reset
    end

    def start_container(id) = post("/containers/#{id}/start")
    def stop_container(id) = post("/containers/#{id}/stop")
    def restart_container(id) = post("/containers/#{id}/restart")

    private

    def get(path, query: {})
      JSON.parse(request(:get, path, query: query).body)
    end

    def post(path)
      request(:post, path)
      true
    end

    def request(method, path, query: {}, body: nil)
      headers = body ? { "Content-Type" => "application/json" } : {}
      response = connection.request(method: method, path: path, query: query,
                                    body: body, headers: headers)
      raise Error, engine_message(response) if response.status >= 400

      response
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
