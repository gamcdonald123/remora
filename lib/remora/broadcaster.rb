module Remora
  # Renders and pushes fleet updates to every subscribed browser.
  module Broadcaster
    def self.refresh_fleet(docker: Remora::Docker.new)
      groups = Container.fleet(docker: docker).group_by(&:compose_project)

      Turbo::StreamsChannel.broadcast_replace_to(
        "fleet",
        target: "fleet",
        partial: "containers/fleet",
        locals: { groups: groups }
      )
    end
  end
end
