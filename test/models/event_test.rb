require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "records a die event with exit code, name and engine time" do
    event = Event.record(
      "Type" => "container", "Action" => "die", "id" => "a" * 64,
      "Actor" => { "ID" => "a" * 64, "Attributes" => { "name" => "web", "exitCode" => "137" } },
      "timeNano" => 1_754_868_000_123_456_789
    )

    assert event.persisted?
    assert_equal "die", event.kind
    assert_equal 137, event.exit_code
    assert_equal "web", event.container_name
    assert_equal "a" * 64, event.docker_id
    assert_in_delta 1_754_868_000.123, event.occurred_at.to_f, 0.001
  end

  test "normalizes health_status actions" do
    event = Event.record(
      "Type" => "container", "Action" => "health_status: unhealthy",
      "Actor" => { "ID" => "b" * 64, "Attributes" => { "name" => "db" } },
      "timeNano" => 1_754_868_000_000_000_000
    )

    assert_equal "health_unhealthy", event.kind
  end

  test "irrelevant actions are not persisted" do
    assert_nil Event.record("Type" => "container", "Action" => "exec_start: ls",
                            "Actor" => { "ID" => "c" * 64, "Attributes" => {} },
                            "timeNano" => 1_754_868_000_000_000_000)
    assert_equal 0, Event.count
  end

  test "prune! removes only events older than 30 days" do
    old = Event.create!(docker_id: "x", kind: "start", occurred_at: 31.days.ago)
    fresh = Event.create!(docker_id: "x", kind: "die", occurred_at: 1.day.ago)

    Event.prune!

    assert_not Event.exists?(old.id)
    assert Event.exists?(fresh.id)
  end
end
