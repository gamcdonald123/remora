require "test_helper"

module Remora
  class DockerTest < ActiveSupport::TestCase
    setup do
      Excon.stubs.clear
      @client = Remora::Docker.new(socket: "/nonexistent/docker.sock")
    end

    teardown do
      Excon.stubs.clear
    end

    test "containers returns the parsed container list" do
      Excon.stub(
        { method: :get, path: "/containers/json" },
        { status: 200, body: [ { "Id" => "abc123", "Names" => [ "/web" ], "State" => "running" } ].to_json }
      )

      containers = @client.containers

      assert_equal 1, containers.size
      assert_equal "abc123", containers.first["Id"]
      assert_equal "running", containers.first["State"]
    end

    test "containers requests all containers including stopped by default" do
      captured = nil
      Excon.stub({ method: :get, path: "/containers/json" }) do |params|
        captured = params
        { status: 200, body: "[]" }
      end

      @client.containers

      assert_includes captured[:query].to_s, "all=true"
    end

    test "inspect_container returns the parsed inspect hash" do
      Excon.stub(
        { method: :get, path: "/containers/abc123/json" },
        { status: 200, body: { "Id" => "abc123", "Config" => { "Image" => "nginx" } }.to_json }
      )

      inspection = @client.inspect_container("abc123")

      assert_equal "nginx", inspection.dig("Config", "Image")
    end

    test "version returns the parsed engine version" do
      Excon.stub(
        { method: :get, path: "/version" },
        { status: 200, body: { "Version" => "29.5.2" }.to_json }
      )

      assert_equal "29.5.2", @client.version["Version"]
    end

    test "start/stop/restart post to the engine action endpoints" do
      posted = []
      Excon.stub({ method: :post }) do |params|
        posted << params[:path]
        { status: 204, body: "" }
      end

      @client.start_container("abc")
      @client.stop_container("abc")
      @client.restart_container("abc")

      assert_equal [ "/containers/abc/start", "/containers/abc/stop", "/containers/abc/restart" ], posted
    end

    test "already-stopped (304) is treated as success" do
      Excon.stub({ method: :post, path: "/containers/abc/stop" }, { status: 304, body: "" })

      assert_nothing_raised { @client.stop_container("abc") }
    end

    test "action failures raise with the engine message" do
      Excon.stub(
        { method: :post, path: "/containers/abc/start" },
        { status: 500, body: { "message" => "driver exploded" }.to_json }
      )

      error = assert_raises(Remora::Docker::Error) { @client.start_container("abc") }
      assert_includes error.message, "driver exploded"
    end

    test "events yields each JSON line from the stream, surviving chunk boundaries" do
      chunks = [
        %({"Type":"container","Action":"die","id":"aaa"}\n{"Type":"cont),
        %(ainer","Action":"start","id":"bbb"}\n)
      ]
      Excon.stub({ method: :get, path: "/events" }) do |params|
        chunks.each { |c| params[:response_block].call(c, nil, nil) }
        { status: 200, body: "" }
      end

      seen = []
      @client.events { |event| seen << [ event["Action"], event["id"] ] }

      assert_equal [ [ "die", "aaa" ], [ "start", "bbb" ] ], seen
    end

    test "stream_logs yields demuxed text chunks for a non-tty container" do
      Excon.stub(
        { method: :get, path: "/containers/abc/json" },
        { status: 200, body: { "Config" => { "Tty" => false } }.to_json }
      )
      frame = [ 1, 0, 0, 0, 6 ].pack("CC3N") + "live!\n"
      Excon.stub({ method: :get, path: "/containers/abc/logs" }) do |params|
        params[:response_block].call(frame, nil, nil)
        { status: 200, body: "" }
      end

      seen = +""
      @client.stream_logs("abc", since: 0) { |text| seen << text }

      assert_equal "live!\n", seen
    end

    test "stream_logs raises TimeoutError on read timeout so callers can ping and resume" do
      Excon.stub(
        { method: :get, path: "/containers/abc/json" },
        { status: 200, body: { "Config" => { "Tty" => true } }.to_json }
      )
      Excon.stub({ method: :get, path: "/containers/abc/logs" }) do
        raise Excon::Errors::Timeout.new("read timeout")
      end

      assert_raises(Remora::Docker::TimeoutError) { @client.stream_logs("abc", since: 0) { } }
    end

    test "exec creates an exec instance, runs it, and returns demuxed output" do
      bodies = []
      Excon.stub({ method: :post, path: "/containers/abc/exec" }) do |params|
        bodies << params[:body]
        { status: 201, body: { "Id" => "exec123" }.to_json }
      end
      frame = [ 1, 0, 0, 0, 5 ].pack("CC3N") + "out\n\n"
      Excon.stub({ method: :post, path: "/exec/exec123/start" }) do |params|
        bodies << params[:body]
        { status: 200, body: frame }
      end

      output = @client.exec("abc", [ "tailscale", "status", "--json" ])

      assert_equal "out\n\n", output
      assert_includes bodies[0], '"Cmd":["tailscale","status","--json"]'
      assert_includes bodies[1], '"Detach":false'
    end

    test "non-2xx responses raise Remora::Docker::Error with the engine message" do
      Excon.stub(
        { method: :get, path: "/containers/missing/json" },
        { status: 404, body: { "message" => "No such container: missing" }.to_json }
      )

      error = assert_raises(Remora::Docker::Error) { @client.inspect_container("missing") }

      assert_includes error.message, "No such container: missing"
    end

    test "socket-level failures raise Remora::Docker::Error" do
      Excon.stub({ method: :get, path: "/version" }) do
        raise Excon::Error::Socket.new(Errno::ENOENT.new("no such socket"))
      end

      assert_raises(Remora::Docker::Error) { @client.version }
    end
  end
end
