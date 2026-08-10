module Remora
  # Heals event history the listener missed (e.g. containers that changed
  # state while Remora itself was down) and owns periodic housekeeping.
  class Reconciler
    INTERVAL = 60
    PRUNES_EVERY = 1440 # cycles ≈ once a day

    def self.start(docker: Remora::Docker.new)
      Thread.new do
        Thread.current.name = "remora-reconciler"
        reconciler = new(docker)
        cycles = 0
        loop do
          sleep INTERVAL
          begin
            reconciler.run_once
            Event.prune! if (cycles += 1) % PRUNES_EVERY == 0
          rescue StandardError => e
            Rails.logger.warn("[remora] reconciler error: #{e.message}")
          end
        end
      end
    end

    def initialize(docker)
      @docker = docker
    end

    def run_once
      drifted = false

      @docker.containers.each do |attrs|
        docker_id = attrs["Id"]
        engine_up = %w[running restarting].include?(attrs["State"])
        last = Event.where(docker_id: docker_id, kind: Event::STATE_CHANGING)
                    .order(:occurred_at).last
        history_up = last&.kind == "start"
        next if last.present? && engine_up == history_up

        Event.create!(
          docker_id: docker_id,
          container_name: Container.new(attrs).name,
          kind: engine_up ? "start" : "die",
          occurred_at: Time.current
        )
        # A fresh baseline isn't drift — no need to repaint anyone's screen.
        drifted = true if last.present?
      end

      Broadcaster.refresh_fleet(docker: @docker) if drifted
    end
  end
end
