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
