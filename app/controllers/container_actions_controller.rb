class ContainerActionsController < ApplicationController
  def start = perform(:start_container)
  def stop = perform(:stop_container)
  def restart = perform(:restart_container)

  private

  def perform(verb)
    docker = Remora::Docker.new
    docker.public_send(verb, params[:id])
    container = Container.fleet(docker: docker).find { |c| c.short_id == params[:id] }

    if container
      render turbo_stream: turbo_stream.replace(container.dom_id, partial: "containers/container", locals: { container: container })
    else
      render turbo_stream: turbo_stream.remove("container_#{params[:id]}")
    end
  rescue Remora::Docker::Error => e
    render turbo_stream: turbo_stream.append("toasts", partial: "shared/toast", locals: { message: e.message })
  end
end
