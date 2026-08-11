require "socket"

# Read-model over one entry of the Engine's /containers/json list.
# Rendered fresh from the socket on every request — never persisted.
class Container
  attr_reader :attrs

  def self.fleet(docker: Remora::Docker.new, hostname: Socket.gethostname)
    containers = docker.containers
                       .map { |attrs| new(attrs) }
                       .reject { |container| container.hosts?(hostname) || container.hidden? }

    merge_sidecars(containers)
      .sort_by { |c| [ c.compose_project ? 0 : 1, c.compose_project.to_s, c.name ] }
  end

  # A tailscale sidecar sharing a network namespace with an app container
  # (either direction of network_mode: container:<id>) folds into the app's
  # row. Network-attached sidecars stay as their own row.
  def self.merge_sidecars(containers)
    by_id = containers.index_by(&:id)
    merged = []

    containers.each do |container|
      next if merged.include?(container.id)

      joined = by_id[container.netns_target]
      partner = [ joined, containers.find { |c| c.netns_target == container.id } ].compact.first

      if partner && (container.tailscale_sidecar? ^ partner.tailscale_sidecar?)
        app, sidecar = container.tailscale_sidecar? ? [ partner, container ] : [ container, partner ]
        app.sidecar = sidecar
        merged << sidecar.id
      end
    end

    containers.reject { |c| merged.include?(c.id) }
  end

  def initialize(attrs)
    @attrs = attrs
  end

  def id = attrs["Id"]
  def short_id = id[0, 12]
  def name = attrs["Names"].to_a.first.to_s.delete_prefix("/")
  def display_name = labels["remora.name"].presence || compose_service.presence || name
  def compose_service = labels["com.docker.compose.service"]
  def hidden? = labels["remora.hide"] == "true"
  def image = attrs["Image"]
  def labels = attrs["Labels"] || {}
  def compose_project = labels["com.docker.compose.project"]
  def status_text = attrs["Status"].to_s
  def dom_id = "container_#{short_id}"

  # Inside a container, the hostname is the short container id — how Remora
  # recognises (and hides) itself.
  def hosts?(hostname) = id.to_s.start_with?(hostname)

  # The merged-in tailscale sidecar, when this row represents a netns pair.
  attr_accessor :sidecar

  def tailscale_sidecar? = image.to_s.start_with?("tailscale/tailscale")
  def tailscale? = sidecar.present? || tailscale_sidecar?

  # The container id this one shares a network namespace with, if any.
  def netns_target
    mode = attrs.dig("HostConfig", "NetworkMode").to_s
    mode.delete_prefix("container:") if mode.start_with?("container:")
  end

  # Containers inherit image labels, so the standard OCI source label gives
  # us the repo link for free on most modern images.
  def repo_url
    url = labels["org.opencontainers.image.source"].to_s
    url if url.start_with?("https://", "http://")
  end

  HTTPS_PORTS = [ 443, 8443 ].freeze

  # Launch targets: {url:} for explicit overrides, {port:, scheme:} for
  # published ports (the host half is resolved in the browser, since rows
  # also render from broadcasts where no request context exists).
  def launch_links
    override = labels["remora.url"].presence
    return [ { url: override } ] if override

    attrs.fetch("Ports", [])
         .select { |p| p["PublicPort"] && p["Type"] == "tcp" && p["IP"] != "127.0.0.1" }
         .map { |p| p["PublicPort"] }
         .uniq.sort
         .map { |port| { port: port, scheme: HTTPS_PORTS.include?(port) ? "https" : "http" } }
  end

  def state_kind
    case attrs["State"]
    when "running" then status_text.include?("(unhealthy)") ? :unhealthy : :running
    when "restarting" then :restarting
    else :exited
    end
  end
end
