require "test_helper"

class ContainerActionsControllerTest < ActionDispatch::IntegrationTest
  SHORT_ID = "a" * 12
  FULL_ID = "a" * 64

  setup { Excon.stubs.clear }
  teardown { Excon.stubs.clear }

  test "stop replaces the container row with its fresh state" do
    Excon.stub({ method: :post, path: "/containers/#{SHORT_ID}/stop" }, { status: 204, body: "" })
    stub_list([ engine_container("State" => "exited", "Status" => "Exited (0) 1 second ago") ])

    post stop_container_path(SHORT_ID), as: :turbo_stream

    assert_response :success
    assert_match %(turbo-stream action="replace" target="container_#{SHORT_ID}"), response.body
    assert_match "state-exited", response.body
  end

  test "a vanished container removes the row" do
    Excon.stub({ method: :post, path: "/containers/#{SHORT_ID}/stop" }, { status: 204, body: "" })
    stub_list([])

    post stop_container_path(SHORT_ID), as: :turbo_stream

    assert_match %(turbo-stream action="remove" target="container_#{SHORT_ID}"), response.body
  end

  test "engine errors surface as a toast" do
    Excon.stub(
      { method: :post, path: "/containers/#{SHORT_ID}/start" },
      { status: 500, body: { "message" => "driver exploded" }.to_json }
    )

    post start_container_path(SHORT_ID), as: :turbo_stream

    assert_response :success
    assert_match %(turbo-stream action="append" target="toasts"), response.body
    assert_match "driver exploded", response.body
  end

  test "actions are not reachable via GET" do
    get "/containers/#{SHORT_ID}/restart"
    assert_response :not_found
  end

  private

  def engine_container(attrs = {})
    { "Id" => FULL_ID, "Names" => [ "/web" ], "State" => "running",
      "Status" => "Up 1 second", "Image" => "nginx", "Labels" => {} }.merge(attrs)
  end

  def stub_list(containers)
    Excon.stub({ method: :get, path: "/containers/json" }, { status: 200, body: containers.to_json })
  end
end
