# Remora 🐟

**A single-container, zero-configuration Docker dashboard — with first-class awareness of Tailscale sidecars.**

Install it on any host and immediately see, control, launch, and monitor every container on that machine. No config files, no onboarding, no accounts. Everything it shows is discovered, not configured.

> A remora is the fish that attaches itself to a larger host and rides along — the original sidecar.

## What you get

- **One screen** — every container, grouped by compose project, updating live (no refresh button, ever)
- **Start / stop / restart** — with an inline confirm on stop; errors surface as toasts
- **Logs** — last 500 lines, instant client-side search, error/warn highlighting, and a live follow mode
- **Launch chips** — published ports become clickable links, correct whether you browse via tailnet, LAN name, or IP
- **Tailscale awareness** — a `tailscale/tailscale` sidecar sharing an app's network namespace folds into one row, and its `tailscale serve` config becomes an `https://app.your-tailnet.ts.net` chip
- **Uptime strips** — 24h up/down history per container from the Docker event stream, with flapping detection

## Install

Minimal (LAN/local):

```bash
docker run -d --name remora \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v remora-data:/data \
  -p 8080:8080 \
  ghcr.io/gamcdonald123/remora:latest
```

**Recommended: tailnet-only.** Remora holds your Docker socket — it should never be exposed to the LAN or internet. The tailnet *is* the auth layer. See [examples/compose.yaml](examples/compose.yaml) for the two-service compose file (Remora behind its own Tailscale sidecar with [examples/ts-serve.json](examples/ts-serve.json)); then open `https://remora.<your-tailnet>.ts.net`.

## Configuration

There is no settings screen and no config file — that's the point. The three tunables are Docker labels on the containers you're *monitoring*:

| Label | Effect |
|---|---|
| `remora.hide: "true"` | Exclude a container from the dashboard |
| `remora.name: "Immich"` | Display-name override (default: compose service name, else container name) |
| `remora.url: "https://immich.example.ts.net"` | Launch-link override; replaces all derived links |

Environment variables on Remora itself (all optional): `TZ`, `DOCKER_SOCKET` (socket path override), `REMORA_HOST_URL` (base URL for port links when the browser's hostname isn't right).

## Security

The mounted `docker.sock` is root-equivalent on the host. Remora's security model is **network placement**: run it tailnet-only as shown above. There is deliberately no in-app auth to misconfigure.

## Development

```bash
bin/setup          # or: bundle install && bin/rails db:prepare
bin/dev            # boots on :3000 against your local Docker socket
bin/rails test     # full suite, no Docker required (Engine API fully stubbed)
```

Rails 8 + Hotwire + SQLite, one container, ~100MB RSS. See [SPEC.md](SPEC.md) for the design and [tasks/plan.md](tasks/plan.md) for how it was built.

## License

MIT
