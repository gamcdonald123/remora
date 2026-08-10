module ContainersHelper
  def launch_chip(link)
    if link[:url]
      host = URI.parse(link[:url]).host rescue link[:url]
      link_to host, link[:url], class: "chip", target: "_blank", rel: "noreferrer"
    elsif (base = ENV["REMORA_HOST_URL"].presence)
      link_to ":#{link[:port]}", "#{base.chomp("/")}:#{link[:port]}",
              class: "chip", target: "_blank", rel: "noreferrer"
    else
      link_to ":#{link[:port]}", "#", class: "chip", target: "_blank", rel: "noreferrer",
              data: { controller: "chip", chip_port_value: link[:port], chip_scheme_value: link[:scheme] }
    end
  end
  # 24h strip as a scaled SVG: green up, red down, grey pre-history.
  def uptime_strip(docker_id)
    segments = Event.timeline_for(docker_id)
    total = segments.last[:to] - segments.first[:from]
    return if total <= 0

    x = 0.0
    rects = segments.map do |segment|
      width = (segment[:to] - segment[:from]) / total * 100
      rect = tag.rect(x: x.round(2), y: 0, width: width.round(2), height: 6,
                      class: "uptime-#{segment[:state]}")
      x += width
      rect
    end

    tag.svg(safe_join(rects), viewBox: "0 0 100 6", preserveAspectRatio: "none",
            class: "uptime-strip", role: "img", "aria-label": "24 hour uptime")
  end
end
