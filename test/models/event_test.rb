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

  test "timeline_for reconstructs up/down segments over the window" do
    now = Time.zone.parse("2026-08-10 12:00")
    id = "t" * 64
    Event.create!(docker_id: id, kind: "start", occurred_at: now - 30.hours)
    Event.create!(docker_id: id, kind: "die", occurred_at: now - 20.hours, exit_code: 1)
    Event.create!(docker_id: id, kind: "start", occurred_at: now - 18.hours)
    Event.create!(docker_id: id, kind: "die", occurred_at: now - 1.hour, exit_code: 0)

    segments = Event.timeline_for(id, window: 24.hours, now: now)

    assert_equal %i[up down up down], segments.map { |s| s[:state] }
    assert_equal now - 24.hours, segments.first[:from]
    assert_equal now, segments.last[:to]
    assert_in_delta 4.hours, segments[0][:to] - segments[0][:from]
    assert_in_delta 17.hours, segments[2][:to] - segments[2][:from]
  end

  test "timeline_for is unknown when there is no history" do
    segments = Event.timeline_for("n" * 64)

    assert_equal [ :unknown ], segments.map { |s| s[:state] }
  end

  test "flapping? detects three dies inside ten minutes" do
    id = "f" * 64
    [ 9, 5, 1 ].each { |m| Event.create!(docker_id: id, kind: "die", occurred_at: m.minutes.ago) }

    assert Event.flapping?(id)
  end

  test "flapping? stays quiet for spread-out dies" do
    id = "s" * 64
    [ 20, 10, 1 ].each { |h| Event.create!(docker_id: id, kind: "die", occurred_at: h.hours.ago) }

    assert_not Event.flapping?(id)
  end

  test "exit_count counts dies in the window" do
    id = "e" * 64
    Event.create!(docker_id: id, kind: "die", occurred_at: 2.hours.ago)
    Event.create!(docker_id: id, kind: "die", occurred_at: 25.hours.ago)
    Event.create!(docker_id: id, kind: "start", occurred_at: 1.hour.ago)

    assert_equal 1, Event.exit_count(id)
  end

  test "prune! removes only events older than 30 days" do
    old = Event.create!(docker_id: "x", kind: "start", occurred_at: 31.days.ago)
    fresh = Event.create!(docker_id: "x", kind: "die", occurred_at: 1.day.ago)

    Event.prune!

    assert_not Event.exists?(old.id)
    assert Event.exists?(fresh.id)
  end
end
