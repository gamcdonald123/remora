require "test_helper"
require "turbo/broadcastable/test_helper"

module Remora
  class ReconcilerTest < ActiveSupport::TestCase
    include Turbo::Broadcastable::TestHelper

    ID = "r" * 64

    setup { Excon.stubs.clear }
    teardown { Excon.stubs.clear }

    test "synthesizes a die when the engine says exited but history says up" do
      Event.create!(docker_id: ID, kind: "start", occurred_at: 2.hours.ago)
      stub_engine(state: "exited")

      streams = capture_turbo_stream_broadcasts("fleet") { reconciler.run_once }

      assert_equal "die", Event.where(docker_id: ID).order(:occurred_at).last.kind
      assert_equal 1, streams.size
    end

    test "synthesizes a start when the engine says running but history says down" do
      Event.create!(docker_id: ID, kind: "die", occurred_at: 2.hours.ago)
      stub_engine(state: "running")

      reconciler.run_once

      assert_equal "start", Event.where(docker_id: ID).order(:occurred_at).last.kind
    end

    test "seeds a baseline event for containers with no history" do
      stub_engine(state: "running")

      reconciler.run_once

      assert_equal [ "start" ], Event.where(docker_id: ID).pluck(:kind)
    end

    test "in-sync containers produce no events and no broadcast" do
      Event.create!(docker_id: ID, kind: "start", occurred_at: 2.hours.ago)
      stub_engine(state: "running")

      streams = capture_turbo_stream_broadcasts("fleet") { reconciler.run_once }

      assert_equal 1, Event.where(docker_id: ID).count
      assert_empty streams
    end

    private

    def reconciler
      Reconciler.new(Remora::Docker.new(socket: "/nonexistent.sock"))
    end

    def stub_engine(state:)
      Excon.stub(
        { method: :get, path: "/containers/json" },
        { status: 200, body: [ { "Id" => ID, "Names" => [ "/drifty" ], "State" => state,
                                 "Status" => "", "Image" => "nginx", "Labels" => {} } ].to_json }
      )
    end
  end
end
