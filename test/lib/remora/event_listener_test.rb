require "test_helper"
require "turbo/broadcastable/test_helper"

module Remora
  class EventListenerTest < ActiveSupport::TestCase
    include Turbo::Broadcastable::TestHelper

    setup do
      Excon.stubs.clear
      Excon.stub(
        { method: :get, path: "/containers/json" },
        { status: 200, body: [ { "Id" => "a" * 64, "Names" => [ "/web" ], "State" => "running",
                                 "Status" => "Up 1 second", "Image" => "nginx", "Labels" => {} } ].to_json }
      )
      @listener = EventListener.new(Remora::Docker.new(socket: "/nonexistent.sock"))
    end

    teardown { Excon.stubs.clear }

    test "container lifecycle events broadcast a fleet refresh" do
      streams = capture_turbo_stream_broadcasts("fleet") do
        @listener.handle({ "Type" => "container", "Action" => "die", "id" => "a" * 64 })
      end

      assert_equal 1, streams.size
      assert_equal "replace", streams.first["action"]
      assert_equal "fleet", streams.first["target"]
    end

    test "health_status events (compound action names) broadcast" do
      streams = capture_turbo_stream_broadcasts("fleet") do
        @listener.handle({ "Type" => "container", "Action" => "health_status: unhealthy" })
      end

      assert_equal 1, streams.size
    end

    test "lifecycle events are persisted" do
      @listener.handle(
        "Type" => "container", "Action" => "die", "id" => "a" * 64,
        "Actor" => { "ID" => "a" * 64, "Attributes" => { "name" => "web", "exitCode" => "0" } },
        "timeNano" => 1_754_868_000_000_000_000
      )

      assert_equal 1, Event.where(kind: "die", docker_id: "a" * 64).count
    end

    test "non-container and irrelevant events are ignored" do
      streams = capture_turbo_stream_broadcasts("fleet") do
        @listener.handle({ "Type" => "network", "Action" => "connect" })
        @listener.handle({ "Type" => "container", "Action" => "exec_start: ls" })
      end

      assert_empty streams
    end
  end
end
