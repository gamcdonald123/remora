require "test_helper"

class StackTest < ActiveSupport::TestCase
  test "build rolls multi-member projects into stacks, flattens singles and standalone" do
    fleet = [
      container("web", project: "immich"),
      container("db", project: "immich"),
      container("vaultwarden", project: "vault"),
      container("scratch", project: nil)
    ]

    entries = Stack.build(fleet)

    assert_equal [ true, false, false ], entries.map(&:stack?)
    assert_equal "immich", entries.first.name
    assert_equal 2, entries.first.containers.size
  end

  test "a stack with all members running is good" do
    stack = Stack.new("immich", [ container("a"), container("b") ])

    assert_equal :running, stack.state_kind
    assert_equal "good", stack.status_text
    assert_empty stack.problem_members
  end

  test "a stack with some members down is degraded and knows its problems" do
    down = container("db", state: "exited")
    stack = Stack.new("immich", [ container("web"), down, container("ml") ])

    assert_equal :degraded, stack.state_kind
    assert_equal "1 of 3 down", stack.status_text
    assert_equal [ down ], stack.problem_members
  end

  test "any unhealthy member marks the stack unhealthy" do
    stack = Stack.new("x", [ container("a"), container("b", status: "Up 1 hour (unhealthy)") ])

    assert_equal :unhealthy, stack.state_kind
    assert_equal "unhealthy", stack.status_text
  end

  test "a fully stopped stack is down" do
    stack = Stack.new("x", [ container("a", state: "exited"), container("b", state: "exited") ])

    assert_equal :exited, stack.state_kind
    assert_equal "down", stack.status_text
  end

  test "a flapping member is a problem even while running" do
    flappy = container("web")
    [ 9, 5, 1 ].each { |m| Event.create!(docker_id: flappy.id, kind: "die", occurred_at: m.minutes.ago) }
    stack = Stack.new("x", [ flappy, container("db", id: "b" * 64) ])

    assert_equal [ flappy ], stack.problem_members
    assert_equal "flapping", stack.status_text
  end

  test "all_links dedupes across members" do
    a = container("a", ports: [ { "PrivatePort" => 80, "PublicPort" => 8080, "Type" => "tcp", "IP" => "0.0.0.0" } ])
    b = container("b", id: "b" * 64, ports: [ { "PrivatePort" => 80, "PublicPort" => 8080, "Type" => "tcp", "IP" => "0.0.0.0" } ])

    assert_equal [ { port: 8080, scheme: "http" } ], Stack.new("x", [ a, b ]).all_links
  end

  private

  def container(name, project: "proj", state: "running", status: "Up 1 hour", id: nil, ports: [])
    labels = project ? { "com.docker.compose.project" => project } : {}
    Container.new(
      "Id" => id || Digest::SHA256.hexdigest(name), "Names" => [ "/#{name}" ], "State" => state,
      "Status" => status, "Image" => "img", "Labels" => labels, "Ports" => ports
    )
  end
end
