module Remora
  # Resolves the tailnet URLs a sidecar serves, by asking the tailscale CLI
  # inside it. Anything unexpected — old CLI, no serve config, sidecar down —
  # degrades to no links; the port chips remain the fallback.
  module Tailscale
    CACHE_TTL = 10.minutes

    def self.links_for(sidecar_id, docker: Remora::Docker.new)
      Rails.cache.fetch(cache_key(sidecar_id), expires_in: CACHE_TTL) do
        compute(sidecar_id, docker)
      end
    end

    def self.invalidate(sidecar_id)
      Rails.cache.delete(cache_key(sidecar_id))
    end

    def self.cache_key(sidecar_id) = "remora/ts-links/#{sidecar_id}"

    def self.compute(sidecar_id, docker)
      status = parse(docker.exec(sidecar_id, %w[tailscale status --json]))
      dns_name = status.dig("Self", "DNSName").to_s.chomp(".")
      return [] if dns_name.blank?

      serve = parse(docker.exec(sidecar_id, %w[tailscale serve status --json]))
      serve.fetch("TCP", {}).keys.sort_by(&:to_i).map do |port|
        scheme = serve["TCP"][port]["HTTPS"] ? "https" : "http"
        default_port = scheme == "https" ? "443" : "80"
        suffix = port.to_s == default_port ? "" : ":#{port}"
        { url: "#{scheme}://#{dns_name}#{suffix}" }
      end
    rescue Remora::Docker::Error
      []
    end

    def self.parse(output)
      JSON.parse(output)
    rescue JSON::ParserError
      {}
    end
  end
end
