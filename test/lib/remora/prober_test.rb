require "test_helper"
require "turbo/broadcastable/test_helper"

module Remora
  class ProberTest < ActiveSupport::TestCase
    include Turbo::Broadcastable::TestHelper

    UP_ID = "a" * 64
    DOWN_ID = "b" * 64

    setup do
      Excon.stubs.clear
      Probes.reset!
      ENV["REMORA_PROBE_HOST"] = "probehost"
    end

    teardown do
      Excon.stubs.clear
      Probes.reset!
      ENV.delete("REMORA_PROBE_HOST")
    end

    test "a probe failure records a transition event and flags the container" do
      stub_fleet
      prober = Prober.new(docker, checker: ->(url) { url.include?("8081") ? false : true })

      streams = capture_turbo_stream_broadcasts("fleet") { prober.run_once }

      assert Probes.down?(DOWN_ID)
      assert_not Probes.down?(UP_ID)
      assert_equal 1, Event.where(kind: "probe_down", docker_id: DOWN_ID).count
      assert_equal 0, Event.where(kind: "probe_up").count
      assert_equal 1, streams.size
    end

    test "recovery records probe_up; steady states record nothing" do
      stub_fleet
      down_then_up = Queue.new
      [ false, true, true ].each { |v| down_then_up << v }
      prober = Prober.new(docker, checker: ->(url) { url.include?("8081") ? down_then_up.pop : true })

      3.times { prober.run_once }

      assert_equal 1, Event.where(kind: "probe_down", docker_id: DOWN_ID).count
      assert_equal 1, Event.where(kind: "probe_up", docker_id: DOWN_ID).count
      assert_not Probes.down?(DOWN_ID)
    end

    test "stopped containers are not probed and lose stale state" do
      Probes.record(UP_ID, :down)
      stub_fleet(up_state: "exited")
      prober = Prober.new(docker, checker: ->(_) { flunk "should not probe" if _.include?("8080"); true })

      prober.run_once

      assert_nil Probes.state(UP_ID)
    end

    private

    def docker = Remora::Docker.new(socket: "/nonexistent.sock")

    def stub_fleet(up_state: "running")
      Excon.stub(
        { method: :get, path: "/containers/json" },
        { status: 200, body: [
          { "Id" => UP_ID, "Names" => [ "/webby" ], "State" => up_state, "Status" => "Up 1 hour", "Image" => "x",
            "Labels" => {}, "Ports" => [ { "PrivatePort" => 80, "PublicPort" => 8080, "Type" => "tcp", "IP" => "0.0.0.0" } ] },
          { "Id" => DOWN_ID, "Names" => [ "/saddy" ], "State" => "running", "Status" => "Up 1 hour", "Image" => "x",
            "Labels" => {}, "Ports" => [ { "PrivatePort" => 80, "PublicPort" => 8081, "Type" => "tcp", "IP" => "0.0.0.0" } ] }
        ].to_json }
      )
    end
  end
end
