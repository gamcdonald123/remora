require "net/http"

module Remora
  # Outside-in HTTP checks of every running container's primary URL —
  # catches "process up, service broken", which Docker state never sees.
  class Prober
    INTERVAL = 60
    TIMEOUT = 4
    POOL = 8

    def self.start(docker: Remora::Docker.new)
      Thread.new do
        Thread.current.name = "remora-prober"
        prober = new(docker)
        loop do
          begin
            prober.run_once
          rescue StandardError => e
            Rails.logger.warn("[remora] prober error: #{e.message}")
          end
          sleep INTERVAL
        end
      end
    end

    def initialize(docker, checker: method(:responding?))
      @docker = docker
      @checker = checker
    end

    def run_once
      fleet = Container.fleet(docker: @docker)
      running, stopped = fleet.partition { |c| c.state_kind != :exited }
      stopped.each { |c| Probes.clear(c.id) }

      targets = running.filter_map { |c| [ c, c.probe_urls ] if c.probe_urls.any? }
      changed = probe_all(targets)

      Broadcaster.refresh_fleet(docker: @docker) if changed
    end

    private

    def probe_all(targets)
      queue = Queue.new
      targets.each { |t| queue << t }
      changed = false

      Array.new([ POOL, targets.size ].min) do
        Thread.new do
          loop do
            container, urls = queue.pop(true)
            changed = true if probe(container, urls)
          rescue ThreadError
            break # queue drained
          end
        end
      end.each(&:join)

      changed
    end

    # Returns true when the verdict flipped (an event was recorded).
    def probe(container, urls)
      state = urls.any? { |url| @checker.call(url) } ? :up : :down
      previous = Probes.state(container.id)
      Probes.record(container.id, state)

      flipped = (previous == :down) != (state == :down)
      return false unless flipped && (previous || state == :down)

      Event.create!(
        docker_id: container.id,
        container_name: container.name,
        kind: "probe_#{state}",
        occurred_at: Time.current
      )
      true
    end

    # Any HTTP answer below 500 counts — auth walls and redirects mean the
    # service is alive. Timeouts, refusals, and TLS failures do not.
    def responding?(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      response = http.request_head(uri.path.presence || "/")
      response.code.to_i < 500
    rescue StandardError
      false
    end
  end
end
