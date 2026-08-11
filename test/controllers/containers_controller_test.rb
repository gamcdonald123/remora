require "test_helper"

class ContainersControllerTest < ActionDispatch::IntegrationTest
  setup { Excon.stubs.clear }
  teardown { Excon.stubs.clear }

  test "index rolls multi-member projects into stacks and flattens the rest" do
    stub_engine_containers([
      { "Id" => "a" * 64, "Names" => [ "/immich-web" ], "State" => "running", "Status" => "Up 3 days",
        "Image" => "immich", "Labels" => { "com.docker.compose.project" => "immich" } },
      { "Id" => "c" * 64, "Names" => [ "/immich-db" ], "State" => "running", "Status" => "Up 3 days",
        "Image" => "postgres", "Labels" => { "com.docker.compose.project" => "immich" } },
      { "Id" => "d" * 64, "Names" => [ "/vaultwarden" ], "State" => "running", "Status" => "Up 3 days",
        "Image" => "vaultwarden/server", "Labels" => { "com.docker.compose.project" => "vault" } },
      { "Id" => "b" * 64, "Names" => [ "/scratchbox" ], "State" => "exited", "Status" => "Exited (0) 2 hours ago",
        "Image" => "alpine", "Labels" => {} }
    ])

    get root_path

    assert_response :success
    # immich (2 members) rolls up: stack row says good, members present for expansion
    assert_select "#stack_immich .stack-row .container-status", "good"
    assert_select "#stack_immich .stack-members #container_#{'a' * 12}"
    # single-member vault project and the standalone container render flat
    assert_select "#container_#{'d' * 12}", /vaultwarden/
    assert_select "#container_#{'b' * 12} .state-dot.state-exited"
  end

  test "a degraded stack marks its problem members for baseline reveal" do
    stub_engine_containers([
      { "Id" => "a" * 64, "Names" => [ "/app-web" ], "State" => "running", "Status" => "Up 3 days",
        "Image" => "x", "Labels" => { "com.docker.compose.project" => "app" } },
      { "Id" => "b" * 64, "Names" => [ "/app-db" ], "State" => "exited", "Status" => "Exited (1) 1 hour ago",
        "Image" => "x", "Labels" => { "com.docker.compose.project" => "app" } }
    ])

    get root_path

    assert_select "#stack_app .stack-row .container-status", "1 of 2 down"
    assert_select "#stack_app .stack-members #container_#{'b' * 12}.problem"
    assert_select "#stack_app .stack-members #container_#{'a' * 12}:not(.problem)"
  end

  test "index shows a connection help message when the socket is unreachable" do
    Excon.stub({ method: :get, path: "/containers/json" }) do
      raise Excon::Error::Socket.new(Errno::ENOENT.new("no such file"))
    end

    get root_path

    assert_response :success
    assert_select ".docker-unreachable", /docker\.sock/
  end

  private

  def stub_engine_containers(containers)
    Excon.stub({ method: :get, path: "/containers/json" }, { status: 200, body: containers.to_json })
  end
end
