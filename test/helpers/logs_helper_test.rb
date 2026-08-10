require "test_helper"

class LogsHelperTest < ActionView::TestCase
  test "error-ish lines are classed sev-error" do
    assert_equal "sev-error", severity_class("2026-08-10 ERROR something broke")
    assert_equal "sev-error", severity_class("[FATAL] out of memory")
    assert_equal "sev-error", severity_class("panic: nil dereference")
  end

  test "warning lines are classed sev-warn" do
    assert_equal "sev-warn", severity_class("WARN slow query")
    assert_equal "sev-warn", severity_class("2026/08/10 warning: deprecated flag")
  end

  test "ordinary lines get no severity class" do
    assert_nil severity_class("GET /up 200 OK")
    assert_nil severity_class("errors_total counter registered")
  end
end
