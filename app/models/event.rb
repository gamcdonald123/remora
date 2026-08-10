# Append-only container state transitions — the source of uptime history.
class Event < ApplicationRecord
  RETENTION = 30.days

  # Engine actions worth keeping. health_status arrives as
  # "health_status: healthy" / "health_status: unhealthy".
  PERSISTED = {
    "start" => "start",
    "die" => "die",
    "oom" => "oom",
    "health_status: healthy" => "health_healthy",
    "health_status: unhealthy" => "health_unhealthy"
  }.freeze

  def self.record(docker_event)
    kind = PERSISTED[docker_event["Action"].to_s]
    return nil unless kind

    actor = docker_event.fetch("Actor", {})
    docker_id = actor["ID"] || docker_event["id"]
    return nil if docker_id.blank?

    exit_code = actor.dig("Attributes", "exitCode")

    create!(
      docker_id: docker_id,
      container_name: actor.dig("Attributes", "name"),
      kind: kind,
      exit_code: exit_code&.to_i,
      occurred_at: occurred_at_from(docker_event)
    )
  end

  def self.occurred_at_from(docker_event)
    nano = docker_event["timeNano"]
    nano ? Time.zone.at(Rational(nano, 1_000_000_000)) : Time.current
  end

  STATE_CHANGING = %w[start die oom].freeze

  # Up/down/unknown segments covering the window, oldest first, for the strip.
  def self.timeline_for(docker_id, window: 24.hours, now: Time.current)
    from = now - window
    prior = where(docker_id: docker_id, kind: STATE_CHANGING)
              .where(occurred_at: ...from).order(:occurred_at).last
    state = prior.nil? ? :unknown : (prior.kind == "start" ? :up : :down)

    segments = []
    cursor = from
    where(docker_id: docker_id, kind: STATE_CHANGING, occurred_at: from..now)
      .order(:occurred_at).each do |event|
      new_state = event.kind == "start" ? :up : :down
      next if new_state == state

      segments << { state: state, from: cursor, to: event.occurred_at }
      state = new_state
      cursor = event.occurred_at
    end
    segments << { state: state, from: cursor, to: now }
    segments
  end

  def self.flapping?(docker_id, now: Time.current)
    dies = where(docker_id: docker_id, kind: "die", occurred_at: (now - 24.hours)..now)
             .order(:occurred_at).pluck(:occurred_at)
    dies.each_cons(3).any? { |first, _, third| third - first <= 10.minutes }
  end

  def self.exit_count(docker_id, window: 24.hours, now: Time.current)
    where(docker_id: docker_id, kind: "die", occurred_at: (now - window)..now).count
  end

  def self.prune!
    where(occurred_at: ...RETENTION.ago).delete_all
  end
end
