require "test_helper"

class LogsControllerTest < ActionDispatch::IntegrationTest
  SHORT_ID = "a" * 12

  setup { Excon.stubs.clear }
  teardown { Excon.stubs.clear }

  test "shows demuxed log lines in the drawer frame" do
    stub_inspect(tty: false)
    frames = frame(1, "hello from stdout\n") + frame(2, "warning from stderr\n")
    stub_logs(frames)

    get logs_container_path(SHORT_ID)

    assert_response :success
    assert_select "turbo-frame#drawer" do
      assert_select ".log-line", 2
    end
    assert_match "hello from stdout", response.body
    assert_match "warning from stderr", response.body
  end

  test "tty containers render raw output without demuxing" do
    stub_inspect(tty: true)
    stub_logs("plain tty line\n")

    get logs_container_path(SHORT_ID)

    assert_match "plain tty line", response.body
  end

  test "tail size is passed through and capped" do
    stub_inspect(tty: true)
    captured = nil
    Excon.stub({ method: :get, path: "/containers/#{SHORT_ID}/logs" }) do |params|
      captured = params[:query].to_s
      { status: 200, body: "" }
    end

    get logs_container_path(SHORT_ID, tail: 99_999)

    assert_includes captured, "tail=4000"
  end

  test "follow streams SSE events and finishes with a closed event" do
    stub_inspect(tty: false)
    line = "2026-08-10T22:00:00.000000000Z stream me <careful>\n"
    frames = frame(1, line)
    Excon.stub({ method: :get, path: "/containers/#{SHORT_ID}/logs" }) do |params|
      params[:response_block].call(frames, nil, nil)
      { status: 200, body: "" }
    end

    get follow_container_path(SHORT_ID)

    assert_response :success
    assert_equal "text/event-stream", response.headers["Content-Type"]
    assert_match "data: <div class=\"log-line", response.body
    assert_match "stream me &lt;careful&gt;", response.body
    refute_match "2026-08-10T22:00:00", response.body
    assert_match "event: closed", response.body
  end

  private

  def frame(type, payload)
    [ type, 0, 0, 0, payload.bytesize ].pack("CC3N") + payload
  end

  def stub_inspect(tty:)
    Excon.stub(
      { method: :get, path: "/containers/#{SHORT_ID}/json" },
      { status: 200, body: { "Id" => "a" * 64, "Name" => "/web", "Config" => { "Tty" => tty, "Labels" => {} } }.to_json }
    )
  end

  def stub_logs(body)
    Excon.stub({ method: :get, path: "/containers/#{SHORT_ID}/logs" }, { status: 200, body: body })
  end
end
