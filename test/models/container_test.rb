require "test_helper"

class ContainerTest < ActiveSupport::TestCase
  test "name strips the leading slash from the docker name" do
    assert_equal "vaultwarden", build_container("Names" => [ "/vaultwarden" ]).name
  end

  test "display_name falls back to the container name" do
    assert_equal "vaultwarden", build_container("Names" => [ "/vaultwarden" ]).display_name
  end

  test "display_name prefers the compose service name over the container name" do
    container = build_container("Names" => [ "/vault-vaultwarden-1" ],
                                "Labels" => { "com.docker.compose.service" => "vaultwarden" })
    assert_equal "vaultwarden", container.display_name
  end

  test "display_name prefers the remora.name label over everything" do
    container = build_container("Labels" => { "remora.name" => "Vaultwarden",
                                              "com.docker.compose.service" => "vaultwarden" })
    assert_equal "Vaultwarden", container.display_name
  end

  test "fleet excludes containers labelled remora.hide" do
    docker = stub_docker([
      { "Id" => "a" * 64, "Names" => [ "/secret" ], "Labels" => { "remora.hide" => "true" } },
      { "Id" => "b" * 64, "Names" => [ "/web" ] }
    ])

    assert_equal [ "web" ], Container.fleet(docker: docker, hostname: "devbox").map(&:name)
  end

  test "compose_project reads the compose label" do
    container = build_container("Labels" => { "com.docker.compose.project" => "propertee" })
    assert_equal "propertee", container.compose_project
  end

  test "compose_project is nil for standalone containers" do
    assert_nil build_container.compose_project
  end

  test "state_kind maps engine states and health to display kinds" do
    assert_equal :running, build_container("State" => "running", "Status" => "Up 3 days").state_kind
    assert_equal :unhealthy, build_container("State" => "running", "Status" => "Up 3 days (unhealthy)").state_kind
    assert_equal :restarting, build_container("State" => "restarting").state_kind
    assert_equal :exited, build_container("State" => "exited", "Status" => "Exited (0) 2 hours ago").state_kind
    assert_equal :exited, build_container("State" => "created").state_kind
  end

  test "status_text exposes the engine's human status" do
    assert_equal "Up 3 days", build_container("Status" => "Up 3 days").status_text
  end

  test "dom_id is stable and based on the short id" do
    assert_equal "container_abcdef123456", build_container("Id" => "abcdef123456" + "0" * 52).dom_id
  end

  test "fleet excludes the container remora itself runs in" do
    docker = stub_docker([
      { "Id" => "aaaa11112222" + "0" * 52, "Names" => [ "/remora" ] },
      { "Id" => "bbbb33334444" + "0" * 52, "Names" => [ "/web" ] }
    ])

    fleet = Container.fleet(docker: docker, hostname: "aaaa11112222")

    assert_equal [ "web" ], fleet.map(&:name)
  end

  test "fleet sorts by compose project then name, standalone containers last" do
    docker = stub_docker([
      { "Id" => "a" * 64, "Names" => [ "/zeta" ] },
      { "Id" => "b" * 64, "Names" => [ "/db" ], "Labels" => { "com.docker.compose.project" => "propertee" } },
      { "Id" => "c" * 64, "Names" => [ "/web" ], "Labels" => { "com.docker.compose.project" => "propertee" } },
      { "Id" => "d" * 64, "Names" => [ "/api" ], "Labels" => { "com.docker.compose.project" => "acme" } }
    ])

    fleet = Container.fleet(docker: docker, hostname: "devbox")

    assert_equal [ "api", "db", "web", "zeta" ], fleet.map(&:name)
  end

  test "launch_links derives one link per published port with scheme by convention" do
    container = build_container("Ports" => [
      { "PrivatePort" => 80, "PublicPort" => 8080, "Type" => "tcp", "IP" => "0.0.0.0" },
      { "PrivatePort" => 80, "PublicPort" => 8080, "Type" => "tcp", "IP" => "::" },
      { "PrivatePort" => 443, "PublicPort" => 8443, "Type" => "tcp", "IP" => "0.0.0.0" }
    ])

    assert_equal [ { port: 8080, scheme: "http" }, { port: 8443, scheme: "https" } ],
                 container.launch_links
  end

  test "launch_links skips loopback-bound, udp, and unpublished ports" do
    container = build_container("Ports" => [
      { "PrivatePort" => 5432, "PublicPort" => 5432, "Type" => "tcp", "IP" => "127.0.0.1" },
      { "PrivatePort" => 53, "PublicPort" => 5353, "Type" => "udp", "IP" => "0.0.0.0" },
      { "PrivatePort" => 9000, "Type" => "tcp" }
    ])

    assert_empty container.launch_links
  end

  test "remora.url label replaces all derived links" do
    container = build_container(
      "Ports" => [ { "PrivatePort" => 80, "PublicPort" => 8080, "Type" => "tcp", "IP" => "0.0.0.0" } ],
      "Labels" => { "remora.url" => "https://immich.tail1234.ts.net" }
    )

    assert_equal [ { url: "https://immich.tail1234.ts.net" } ], container.launch_links
  end

  test "fleet merges an app with its netns tailscale sidecar (app joins sidecar)" do
    sidecar_id = "5" * 64
    docker = stub_docker([
      { "Id" => sidecar_id, "Names" => [ "/vault-ts-1" ], "Image" => "tailscale/tailscale:latest" },
      { "Id" => "6" * 64, "Names" => [ "/vaultwarden" ], "Image" => "vaultwarden/server",
        "HostConfig" => { "NetworkMode" => "container:#{sidecar_id}" } }
    ])

    fleet = Container.fleet(docker: docker, hostname: "devbox")

    assert_equal [ "vaultwarden" ], fleet.map(&:name)
    assert fleet.first.tailscale?
    assert_equal "vault-ts-1", fleet.first.sidecar.name
  end

  test "fleet merges when the sidecar joins the app's namespace" do
    app_id = "7" * 64
    docker = stub_docker([
      { "Id" => app_id, "Names" => [ "/immich" ], "Image" => "immich/server" },
      { "Id" => "8" * 64, "Names" => [ "/immich-ts" ], "Image" => "tailscale/tailscale:v1.86",
        "HostConfig" => { "NetworkMode" => "container:#{app_id}" } }
    ])

    fleet = Container.fleet(docker: docker, hostname: "devbox")

    assert_equal [ "immich" ], fleet.map(&:name)
    assert fleet.first.tailscale?
  end

  test "a network-attached sidecar keeps its own row, badged" do
    docker = stub_docker([
      { "Id" => "9" * 64, "Names" => [ "/propertee-tailscale-1" ], "Image" => "tailscale/tailscale:latest",
        "HostConfig" => { "NetworkMode" => "propertee_default" } },
      { "Id" => "0" * 64, "Names" => [ "/propertee-web-1" ], "Image" => "rails-app",
        "HostConfig" => { "NetworkMode" => "propertee_default" } }
    ])

    fleet = Container.fleet(docker: docker, hostname: "devbox")

    assert_equal 2, fleet.size
    sidecar_row = fleet.find { |c| c.name == "propertee-tailscale-1" }
    assert sidecar_row.tailscale?
    assert_nil sidecar_row.sidecar
  end

  test "probe_urls: label overrides layered over discovered links" do
    ENV["REMORA_PROBE_HOST"] = "probehost"
    ports = [ { "PrivatePort" => 80, "PublicPort" => 8080, "Type" => "tcp", "IP" => "0.0.0.0" },
              { "PrivatePort" => 22000, "PublicPort" => 22000, "Type" => "tcp", "IP" => "0.0.0.0" } ]

    assert_equal [ "http://probehost:8080", "http://probehost:22000" ],
                 build_container("Ports" => ports).probe_urls
    assert_empty build_container("Ports" => ports, "Labels" => { "remora.probe" => "false" }).probe_urls
    assert_equal [ "http://probehost:8080/health" ],
                 build_container("Ports" => ports, "Labels" => { "remora.probe" => "/health" }).probe_urls
    assert_equal [ "https://x.example/ping" ],
                 build_container("Labels" => { "remora.probe" => "https://x.example/ping" }).probe_urls
    assert_empty build_container.probe_urls
  ensure
    ENV.delete("REMORA_PROBE_HOST")
  end

  test "repo_url comes from the OCI source label" do
    container = build_container("Labels" => { "org.opencontainers.image.source" => "https://github.com/dani-garcia/vaultwarden" })

    assert_equal "https://github.com/dani-garcia/vaultwarden", container.repo_url
  end

  test "repo_url is nil when absent or not a web url" do
    assert_nil build_container.repo_url
    assert_nil build_container("Labels" => { "org.opencontainers.image.source" => "git@github.com:x/y.git" }).repo_url
  end

  private

  def build_container(attrs = {})
    Container.new({ "Id" => "f" * 64, "Names" => [ "/box" ], "State" => "running", "Status" => "Up 1 second", "Image" => "nginx:latest", "Labels" => {} }.merge(attrs))
  end

  def stub_docker(containers)
    docker = Object.new
    docker.define_singleton_method(:containers) { |all: true| containers }
    docker
  end
end
