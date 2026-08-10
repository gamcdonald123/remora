class ContainersController < ApplicationController
  def index
    @groups = Container.fleet.group_by(&:compose_project)
  rescue Remora::Docker::Error => e
    @docker_error = e.message
  end
end
