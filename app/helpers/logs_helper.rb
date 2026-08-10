module LogsHelper
  # Cheap visual classification — word-boundary matches so "errors_total"
  # doesn't light up red.
  def severity_class(line)
    case line
    when /\b(error|fatal|panic|exception)\b/i then "sev-error"
    when /\b(warn|warning)\b/i then "sev-warn"
    end
  end
end
