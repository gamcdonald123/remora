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

  def self.prune!
    where(occurred_at: ...RETENTION.ago).delete_all
  end
end
