module Remora
  # Current probe verdict per container — memory only; transitions persist
  # as events. Empty after a restart until the first probe cycle (~60s).
  module Probes
    LOCK = Mutex.new
    @status = {}

    def self.record(docker_id, state)
      LOCK.synchronize { @status[docker_id] = state }
    end

    def self.clear(docker_id)
      LOCK.synchronize { @status.delete(docker_id) }
    end

    def self.state(docker_id)
      LOCK.synchronize { @status[docker_id] }
    end

    def self.down?(docker_id) = state(docker_id) == :down

    def self.reset!
      LOCK.synchronize { @status.clear }
    end

    # Where host-published ports are reachable from inside the container:
    # the default-route gateway. Overridable; falls back to localhost for
    # non-container development.
    def self.probe_host
      @probe_host ||= ENV["REMORA_PROBE_HOST"].presence || gateway_ip || "localhost"
    end

    def self.gateway_ip
      line = File.readlines("/proc/net/route").find { |l| l.split[1] == "00000000" }
      line && [ line.split[2] ].pack("H8").unpack("C4").reverse.join(".")
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end
  end
end
