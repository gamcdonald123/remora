Rails.application.config.after_initialize do
  # Background threads belong only in a real server process — never in the
  # console, runner, rake tasks, or the test suite.
  serving = defined?(Rails::Server) || ENV["REMORA_BACKGROUND"] == "1"
  next unless serving && !Rails.env.test?

  Rails.logger.info("[remora] starting event listener, reconciler, and prober")
  Remora::EventListener.start
  Remora::Reconciler.start
  Remora::Prober.start
end
