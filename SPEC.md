# Remora — Specification v0.1

> **One-liner:** A single-container, zero-configuration Docker dashboard. Install it on any host and immediately see, control, launch, and monitor every container on that machine — with first-class awareness of Tailscale sidecars.

*(A remora is the fish that attaches itself to a larger host and rides along — the original sidecar.)*

---

## 1. Principles

These are constraints, not aspirations. Every feature decision is tested against them.

1. **Zero configuration.** The app is fully populated the moment it starts, because everything it shows is *discovered* from the Docker API, never configured in the app. There is no settings screen, no onboarding, no account creation, and no config file.
2. **One screen.** The container list *is* the app. Logs open as a drawer/panel over it. If a feature needs a second level of navigation, it is out of scope.
3. **Configuration lives in labels.** The only tunables are Docker labels on the *monitored* containers (see §7) plus a handful of env vars on Remora itself. Labels live in the user's compose files — which is already their source of truth.
4. **The tailnet is the auth layer.** No user system, no login. The recommended install puts Remora behind its own Tailscale sidecar. It must never be exposed to LAN or internet.
5. **Turnkey install.** One paste-able block. No dependencies beyond the Docker socket.

**Litmus test for any future feature:** does it still work with zero configuration? If no, it doesn't go in.

## 2. v1 scope

| In | Out (deliberately) |
|---|---|
| Container list with live state | Stack / compose management |
| Start / stop / restart actions | Image management, pulls, updates |
| Log viewer with search & follow | Notifications |
| Clickable port / launch links | User accounts & roles |
| Tailscale sidecar detection | Multi-host (phase 3) |
| Uptime timeline from Docker events | HTTP probes (phase 2) |
| | CPU/memory graphs (phase 2) |
| | Plugins, themes, settings UI |

## 3. Install

Minimal:

```bash
docker run -d --name remora \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v remora-data:/data \
  -p 8080:8080 \
  ghcr.io/gamcdonald123/remora:latest
```

Recommended (tailnet-only, the documented default):

```yaml
services:
  ts-remora:
    image: tailscale/tailscale:latest
    hostname: remora
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY}
      - TS_SERVE_CONFIG=/config/serve.json
      - TS_STATE_DIR=/var/lib/tailscale
    volumes:
      - ts-state:/var/lib/tailscale
      - ./ts-serve.json:/config/serve.json:ro
    cap_add: [net_admin, sys_module]
    restart: unless-stopped

  remora:
    image: ghcr.io/gamcdonald123/remora:latest
    network_mode: service:ts-remora
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - remora-data:/data
    depends_on: [ts-remora]
    restart: unless-stopped

volumes:
  ts-state:
  remora-data:
```

Remora env vars (all optional): `TZ`, `DOCKHAND_HOST_URL` (base URL override for host-published port links; default is derived from the browser's `Host` header — see §6.3).

## 4. UI

**One screen: the fleet view.** A table/card list, one row per container (compose-project grouping as visual section headers only). Per row:

- State dot (running / exited / restarting / unhealthy) + display name
- Uptime ("up 3d 4h", or "exited 2h ago") + restart count (highlighted if > 0 recently)
- Launch links: one chip per published port or Tailscale serve URL (§6). Click → opens in new tab
- Tailscale badge when the container is behind a detected TS sidecar
- Actions: start / stop / restart. Stop asks for a single inline confirm. Actions are optimistic with Turbo Stream reconciliation
- Mini uptime bar: last 24h as a strip (green/red/grey) built from the events table

Rows update live (Docker events → Turbo Streams). No refresh button needed, ever.

**Logs drawer.** Clicking a row opens a full-height drawer:

- Loads last 500 lines (`tail=500`), stdout+stderr merged, timestamps toggleable
- **Follow** toggle: live tail streamed to the browser
- **Search box:** instant client-side filter over the loaded window (Stimulus, no round-trip); "load more" fetches further back
- Level highlighting by cheap regex (error/warn) — visual only, not a parser

That is the entire app.

## 5. Core behaviors

### 5.1 Discovery
On boot and on every Docker `start`/`die`/`create`/`destroy` event, Remora lists containers (including stopped) via the Docker Engine API over the mounted socket. Remora hides itself and its own sidecar by default.

### 5.2 Actions
Start / stop / restart map 1:1 to Engine API calls. Failures surface as inline toasts with the API error text. No queue needed — these are fast, synchronous calls.

### 5.3 Uptime monitoring (v1 = state history, not probes)
Remora subscribes to the Docker events stream and records every state transition (`start`, `die` + exit code, `oom`, `health_status`) into SQLite. From this it renders: current uptime, the 24h strip, restart counts, and "flapping" detection (≥3 restarts in 10 min → badge). A 60s reconciliation poll heals any missed events (e.g. after Remora itself restarts). HTTP probing à la Uptime Kuma is explicitly phase 2.

## 6. Tailscale awareness (the differentiator)

### 6.1 Sidecar detection
A container is a **TS sidecar** if its image matches `tailscale/tailscale*` **or** it has a `TS_AUTHKEY`/`TS_STATE_DIR` env var. A container is **behind** a sidecar if its `HostConfig.NetworkMode` is `container:<sidecar-id>` (what compose's `network_mode: service:x` becomes).

### 6.2 Tailnet URL resolution
For each sidecar, Remora runs (via the Engine API exec endpoint, cached, refreshed on events):

1. `tailscale status --json` → `Self.DNSName` → the MagicDNS hostname
2. `tailscale serve status --json` → which ports are served, HTTP vs HTTPS

The paired app container's launch chip becomes `https://<dnsname>` (or `https://<dnsname>:<port>` for non-443 serves). The sidecar and app are rendered as **one merged row** — the app's name, the sidecar's URL, a TS badge.

### 6.3 Plain published ports
For ordinary `-p` published ports, the link is `http(s)://<browser Host header, port stripped>:<published port>` — zero config, and automatically correct whether the user is browsing via tailnet hostname, mDNS name, or IP. `DOCKHAND_HOST_URL` overrides when needed. Ports 443/8443 get `https`, everything else `http`; `remora.url` (§7) overrides per container.

## 7. Label schema

Exactly three labels, namespace `remora.`:

| Label | Effect |
|---|---|
| `remora.hide: "true"` | Exclude container from the dashboard |
| `remora.name: "Immich"` | Display-name override (default: compose service name, else container name) |
| `remora.url: "https://immich.example.ts.net"` | Launch-link override; replaces all derived links |

Any need that can't be met by these three gets designed as discovery, not as a fourth label — additions require a very good reason.

## 8. Architecture (Rails)

| Concern | Choice |
|---|---|
| Framework | Rails 8.x, Ruby 3.4 with YJIT |
| Frontend | Hotwire (Turbo Streams + Stimulus), importmap, Propshaft — no Node in the image |
| DB | SQLite (WAL) in `/data` — the only volume |
| Real-time | ActionCable with `async` adapter (single process, no Redis, no solid_cable) |
| Docker API | Thin hand-rolled client over the unix socket using **Excon** (`unix:///` + `:socket`). No docker-api gem — the Engine API is stable and we use ~8 endpoints |
| Background work | No job framework. Two long-lived threads started from a Puma plugin: (1) Docker events listener → SQLite + Turbo broadcasts; (2) 60s reconciler |
| Log streaming | `ActionController::Live` SSE per open drawer, proxying the Engine API `/logs?follow=1` chunked stream |
| Server | Puma, 1 worker, ~5 threads, jemalloc |
| Image | Multi-stage Dockerfile on `ruby:3.4-slim`; target < 300MB image |

**Memory budget: < 250MB RSS steady-state** (the DXP2800 test: it must be a good citizen on an 8GB NAS). Measured in CI as a smoke check.

### Data model (3 tables)

- `containers` — cached snapshot of discovery (docker_id, name, display_name, compose_project, state, health, image, labels JSON, links JSON, sidecar linkage). Rebuilt from Docker at any time; SQLite is a cache here, not a source of truth.
- `events` — append-only state transitions (container docker_id, kind, exit_code, occurred_at). Source of the uptime strip. Pruned at 30 days.
- `exec_cache` — memoized `tailscale status/serve` results per sidecar with fetched_at.

## 9. Security posture

- The mounted docker.sock is **root-equivalent on the host**. This is inherent to the product; the mitigation is network placement, not app auth.
- Hard rule shipped in the docs: tailnet-only. The recommended compose (§3) *is* the security model.
- No auth in-app for v1. Revisit only if a real need appears (e.g. `tailscale whois` header-based identity display — a natural phase-2 nicety, still zero-config).
- Actions are POSTs with CSRF protection; no GET has side effects.

## 10. Roadmap

- **Phase 1 (v1):** everything above.
- **Phase 2:** HTTP health probes (auto-derived from launch URLs — still zero-config), `tailscale whois` identity chip, CPU/mem sparklines from the stats API, ntfy/webhook notifications.
- **Phase 3:** multi-host — one Remora instance federating read-only over the tailnet to agents on other machines (Dozzle's agent model as prior art).

## 11. Open questions

1. Grouped compose projects: collapse by default or flat list? (Lean: flat, section headers only.)
2. Does `tailscale serve status --json` cover all serve configs in current TS versions, or should we also parse `TS_SERVE_CONFIG` files? Verify during build.
