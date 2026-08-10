require "socket"

# Read-model over one entry of the Engine's /containers/json list.
# Rendered fresh from the socket on every request — never persisted.
class Container
  attr_reader :attrs

  def self.fleet(docker: Remora::Docker.new, hostname: Socket.gethostname)
    docker.containers
          .map { |attrs| new(attrs) }
          .reject { |container| container.hosts?(hostname) || container.hidden? }
          .sort_by { |c| [ c.compose_project ? 0 : 1, c.compose_project.to_s, c.name ] }
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
