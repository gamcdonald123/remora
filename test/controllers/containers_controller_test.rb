require "test_helper"

class ContainersControllerTest < ActionDispatch::IntegrationTest
  setup { Excon.stubs.clear }
  teardown { Excon.stubs.clear }

  test "index lists containers grouped by compose project" do
    stub_engine_containers([
      { "Id" => "a" * 64, "Names" => [ "/vaultwarden" ], "State" => "running", "Status" => "Up 3 days",
        "Image" => "vaultwarden/server", "Labels" => { "com.docker.compose.project" => "vault" } },
      { "Id" => "b" * 64, "Names" => [ "/scratchbox" ], "State" => "exited", "Status" => "Exited (0) 2 hours ago",
        "Image" => "alpine", "Labels" => {} }
    ])

    get root_path

    assert_response :success
    assert_select "section[data-project='vault']" do
      assert_select "h2", "vault"
      assert_select "#container_#{'a' * 12}", /vaultwarden/
    end
    assert_select "#container_#{'b' * 12}", /scratchbox/
    assert_select "#container_#{'b' * 12} .state-dot.state-exited"
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
