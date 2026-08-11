# A compose project rolled up into one top-level row. The baseline view
# answers "is everything okay?" — members surface only on demand or when
# they're a problem.
class Stack
  attr_reader :name, :containers

  # Fleet (sorted) → top-level entries: multi-member projects become stacks;
  # single-member projects and standalone containers stay as themselves.
  def self.build(fleet)
    fleet.group_by(&:compose_project).flat_map do |project, members|
      if project.nil? || members.size == 1
        members
      else
        new(project, members)
      end
    end
  end

  def initialize(name, containers)
    @name = name
    @containers = containers
  end

  def stack? = true
  def dom_id = "stack_#{name.parameterize}"

  def problem_members = containers.select(&:problem?)

  def state_kind
    kinds = containers.map(&:state_kind)
    return :exited if kinds.all?(:exited)
    return :unhealthy if kinds.include?(:unhealthy)
    return :running if problem_members.empty?

    :degraded
  end

  def status_text
    case state_kind
    when :running then "good"
    when :exited then "down"
    when :unhealthy then "unhealthy"
    else
      down = containers.count { |c| c.state_kind == :exited }
      down.positive? ? "#{down} of #{containers.size} down" : "flapping"
    end
  end

  def tailscale? = containers.any?(&:tailscale?)

  def all_links = containers.flat_map(&:all_links).uniq
end
