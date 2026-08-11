class ContainersController < ApplicationController
  def index
    @fleet = Container.fleet
  rescue Remora::Docker::Error => e
    @docker_error = e.message
  end
end
