module Remora
  # Renders and pushes fleet updates to every subscribed browser.
  module Broadcaster
    def self.refresh_fleet(docker: Remora::Docker.new)
      Turbo::StreamsChannel.broadcast_replace_to(
        "fleet",
        target: "fleet",
        partial: "containers/fleet",
        locals: { fleet: Container.fleet(docker: docker) }
      )
    end
  end
end
