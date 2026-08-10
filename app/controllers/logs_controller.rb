class LogsController < ApplicationController
  MAX_TAIL = 4000
  DEFAULT_TAIL = 500

  def show
    @id = params[:id]
    @tail = params.fetch(:tail, DEFAULT_TAIL).to_i.clamp(1, MAX_TAIL)
    @timestamps = params[:timestamps] == "1"

    docker = Remora::Docker.new
    @container_name = docker.inspect_container(@id)["Name"].to_s.delete_prefix("/")
    @lines = docker.logs(@id, tail: @tail, timestamps: @timestamps).split("\n")
  rescue Remora::Docker::Error => e
    @docker_error = e.message
  end
end
