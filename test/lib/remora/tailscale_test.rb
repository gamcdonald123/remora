require "test_helper"

module Remora
  class TailscaleTest < ActiveSupport::TestCase
    SIDECAR_ID = "s" * 64

    test "links_for builds tailnet urls from status and serve output" do
      docker = docker_returning(
        status: file_fixture("ts_status.json").read,
        serve: file_fixture("ts_serve.json").read
      )

      links = Tailscale.links_for(SIDECAR_ID, docker: docker)

      assert_equal [
        { url: "https://vaultwarden.example-tailnet.ts.net" },
        { url: "http://vaultwarden.example-tailnet.ts.net:8080" }
      ], links
    end

    test "no serve config yields no links" do
      docker = docker_returning(status: file_fixture("ts_status.json").read, serve: "{}")

      assert_empty Tailscale.links_for(SIDECAR_ID, docker: docker)
    end

    test "unparseable output degrades to no links rather than raising" do
      docker = docker_returning(status: "tailscale: command not found", serve: "junk")

      assert_empty Tailscale.links_for(SIDECAR_ID, docker: docker)
    end

    test "exec failure degrades to no links" do
      docker = Object.new
      def docker.exec(*) = raise(Remora::Docker::Error, "container not running")

      assert_empty Tailscale.links_for(SIDECAR_ID, docker: docker)
    end

    private

    def docker_returning(status:, serve:)
      docker = Object.new
      docker.define_singleton_method(:exec) do |_id, cmd|
        cmd.include?("serve") ? serve : status
      end
      docker
    end
  end
end
