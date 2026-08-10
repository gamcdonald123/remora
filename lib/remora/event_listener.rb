module Remora
  # Long-lived background thread: follows the Engine's /events stream and
  # broadcasts a fleet refresh over Turbo Streams on every relevant change.
  class EventListener
    RELEVANT_ACTIONS = %w[
      create start restart die stop kill oom pause unpause
      destroy rename health_status
    ].freeze

    def self.start(docker: Remora::Docker.new)
      Thread.new do
        Thread.current.name = "remora-events"
        new(docker).run
      end
    end

    def initialize(docker)
      @docker = docker
      # The streaming connection is busy for the lifetime of the events
      # request — fleet queries during handling need their own connection,
      # or they'd kill the stream mid-read.
      @query_docker = Remora::Docker.new(socket: docker.socket)
      @last_seen = nil
    end

    def run
      backoff = 1
      loop do
        @docker.events(since: @last_seen) do |event|
          backoff = 1
          @last_seen = event["time"]
          handle(event)
        end
        # Stream ended cleanly (engine restart) — reconnect after a beat.
        sleep backoff
      rescue StandardError => e
        Rails.logger.warn("[remora] event stream error: #{e.message}; reconnecting in #{backoff}s")
        sleep backoff
        backoff = [ backoff * 2, 30 ].min
      end
    end

    def handle(event)
      return unless event["Type"] == "container"
      # Compound actions arrive as e.g. "health_status: unhealthy", "exec_start: ls".
      action = event["Action"].to_s.split(":").first
      return unless RELEVANT_ACTIONS.include?(action)

      Event.record(event)
      Tailscale.invalidate(event["id"]) if event["id"]
      Broadcaster.refresh_fleet(docker: @query_docker)
    rescue StandardError => e
      Rails.logger.warn("[remora] event handling error: #{e.message}")
    end
  end
end
