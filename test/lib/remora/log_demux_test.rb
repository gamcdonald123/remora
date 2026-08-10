require "test_helper"

module Remora
  class LogDemuxTest < ActiveSupport::TestCase
    STDOUT_T = 1
    STDERR_T = 2

    test "concatenates stdout and stderr frames in arrival order" do
      body = frame(STDOUT_T, "line one\n") + frame(STDERR_T, "oops\n") + frame(STDOUT_T, "line two\n")

      assert_equal "line one\noops\nline two\n", LogDemux.call(body)
    end

    test "handles payloads split across large frames" do
      big = "x" * 70_000
      assert_equal big, LogDemux.call(frame(STDOUT_T, big))
    end

    test "a truncated trailing frame yields what it can without raising" do
      whole = frame(STDOUT_T, "complete\n")
      truncated = frame(STDOUT_T, "partial payload that got cut")[0, 12]

      assert_equal "complete\npart", LogDemux.call(whole + truncated)
    end

    test "empty body yields empty string" do
      assert_equal "", LogDemux.call("")
    end

    private

    def frame(type, payload)
      [ type, 0, 0, 0, payload.bytesize ].pack("CC3N") + payload
    end
  end
end
