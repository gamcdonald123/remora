class LogsController < ApplicationController
  include ActionController::Live

  MAX_TAIL = 4000
  DEFAULT_TAIL = 500
  # RFC3339Nano prefix the engine adds when timestamps are requested.
  TS_PREFIX = /\A(\S+) /

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

  def follow
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["X-Accel-Buffering"] = "no"
    response.headers["Last-Modified"] = Time.now.httpdate

    docker = Remora::Docker.new
    show_timestamps = params[:timestamps] == "1"
    since = Time.now.to_f
    pending = +""

    loop do
      docker.stream_logs(params[:id], since: since) do |text|
        pending << text
        *complete, pending = pending.split("\n", -1)
        complete.each do |raw|
          timestamp = raw[TS_PREFIX, 1]
          since = [ since, Time.iso8601(timestamp).to_f + 0.000001 ].max if timestamp
          line = show_timestamps ? raw : raw.sub(TS_PREFIX, "")
          response.stream.write("data: #{line_html(line)}\n\n")
        end
      end
      break # stream closed by the engine — the container stopped
    rescue Remora::Docker::TimeoutError
      # Quiet container: ping so a vanished client raises and frees the thread.
      response.stream.write(": ping\n\n")
    end

    response.stream.write("event: closed\ndata: done\n\n")
  rescue Remora::Docker::Error, ActionController::Live::ClientDisconnected, IOError
    # Client went away or the engine call failed — nothing to render on SSE.
  ensure
    response.stream.close
  end

  private

  def line_html(line)
    %(<div class="log-line #{helpers.severity_class(line)}">#{ERB::Util.html_escape(line)}</div>)
  end
end
