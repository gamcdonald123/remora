# Implementation Plan: Remora v1

Derived from [SPEC.md](../SPEC.md). Companion checklist: [todo.md](todo.md).

## Overview

Build Remora v1 in six phases of vertical slices: each phase ends with a working, demoable app that does strictly more than the last. Order follows the dependency graph and puts the riskiest plumbing (background event thread, ActionCable broadcasts from outside the request cycle, chunked-stream proxying) as early as possible.

## Dependency graph

```
Remora::Docker (Excon socket client)
    │
    ├── Container presenter (labels, state) ──► Fleet view (index)
    │                                              │
    ├── Actions (start/stop/restart) ──────────────┤
    │                                              │
    ├── Events stream (thread) ──┬── Live row updates (Turbo Streams)
    │                            └── events table ──► Uptime strip / badges
    │                                                     ▲
    ├── Reconciler (60s poll) ────────────────────────────┘
    │
    ├── Logs endpoints (tail / follow SSE) ──► Logs drawer UI
    │
    └── Exec endpoint ──► Tailscale detection ──► Tailnet launch chips
                                                  (plain port chips need only the presenter)

Packaging (Dockerfile, GHCR, docs) depends on everything above.
```

## Architecture decisions

- **No `containers` table for v1.** The fleet view renders straight from the Docker API on each request (it's a local unix socket — sub-millisecond). SQLite stores only `events` (uptime history). This amends SPEC §8's three-table model to one table; `exec_cache` becomes `Rails.cache` (memory store) with event-driven invalidation, since a single process needs no shared cache. Revisit only if multi-host (phase 3 of the spec) happens.
- **Background work = two threads in a Puma plugin** (events listener, reconciler), exactly per spec. Broadcasts go through `Turbo::StreamsChannel.broadcast_*`, which is thread-safe with the async cable adapter in-process.
- **Docker log streams are multiplexed** (8-byte frame headers on stdout/stderr) unless the container has a TTY. The client must demux both cases — this is the classic gotcha, handled in the log tasks with fixture-based tests.
- **Testing:** Minitest + `Excon.stub` with fixture JSON captured from a real Docker Engine. A small set of integration tests run only when a real socket is present (`RemoraTestHelpers.docker?`).

---

## Phase 1 — See (foundation + fleet view)

### Task 1: Docker socket client

**Description:** `Remora::Docker` — a thin Excon client over `/var/run/docker.sock` (path overridable via `DOCKER_SOCKET`). Methods for v1: `containers(all: true)`, `inspect_container(id)`, `version`. Typed error (`Remora::Docker::Error`) wrapping HTTP/socket failures with the Engine's error text.

**Acceptance criteria:**
- [ ] `Remora::Docker.new.containers` returns parsed JSON array against a stubbed socket
- [ ] Socket-missing and non-2xx responses raise `Remora::Docker::Error` with the Engine message
- [ ] No gem dependency beyond excon

**Verification:** `bin/rails test test/lib/docker_client_test.rb`; manual: `bin/rails runner 'p Remora::Docker.new.version'` against Docker Desktop.

**Dependencies:** None. **Files:** `lib/remora/docker.rb`, `test/lib/docker_client_test.rb`, fixtures. **Scope:** S

### Task 2: Fleet view page

**Description:** Root route renders every discovered container: state dot, name, image, "up 3d 4h"/"exited 2h ago" (from `State`/`Status`), grouped under compose-project section headers (flat list, headers only — resolves SPEC open question 1). Remora hides itself (self-detection via hostname == container id). Server renders on each request; no DB.

**Acceptance criteria:**
- [ ] `/` lists all containers incl. stopped ones, grouped by `com.docker.compose.project`
- [ ] Remora's own container absent from the list
- [ ] State dot reflects running / exited / restarting / unhealthy

**Verification:** controller test with stubbed client; manual against Docker Desktop with 2+ compose projects running.

**Dependencies:** 1. **Files:** `ContainersController`, `Container` presenter (ActiveModel PORO), index view + row partial, routes, CSS. **Scope:** M

### Task 3: Label handling

**Description:** Honor `remora.hide` and `remora.name` in the presenter (`remora.url` lands with launch chips, Task 12).

**Acceptance criteria:**
- [ ] `remora.hide: "true"` removes a container from the fleet view
- [ ] `remora.name` overrides display name; fallback order: label → compose service → container name

**Verification:** presenter unit tests; manual with a labeled test container.

**Dependencies:** 2. **Files:** `app/models/container.rb`, tests. **Scope:** XS

### ✅ Checkpoint 1
- [ ] Fleet view shows the real local Docker fleet, grouped and labeled correctly
- [ ] Test suite green; no DB migrations exist yet (by design)

---

## Phase 2 — Control (actions + live updates)

### Task 4: Start / stop / restart actions

**Description:** POST endpoints per container calling the Engine API; buttons on each row. Stop requires a one-click inline confirm (Stimulus). Failures render an inline toast with the Engine's error text. Success re-renders the row via Turbo Stream response.

**Acceptance criteria:**
- [ ] Each action works against a real container and the row reflects the new state without full-page reload
- [ ] Stopping requires a second click; API errors surface as a toast, not a 500
- [ ] All actions are POSTs with CSRF protection

**Verification:** controller tests (stubbed success + Engine error); manual start/stop/restart cycle on a scratch nginx container.

**Dependencies:** 2. **Files:** client additions, `ContainerActionsController`, row partial, Stimulus confirm + toast controllers. **Scope:** M

### Task 5: Events listener → live rows

**Description:** Puma-plugin background thread streaming `/events` (chunked JSON). On `start|die|stop|restart|health_status|create|destroy`, re-inspect the container and broadcast a Turbo Stream row replace/append/remove to a `fleet` stream the index subscribes to. Reconnect with capped backoff; thread must never kill the server. **Highest-risk task — do not defer.**

**Acceptance criteria:**
- [ ] `docker stop x` in a terminal updates every open browser within ~1s, no refresh
- [ ] Killing Docker Desktop and restarting it: Remora reconnects and resumes updates
- [ ] Listener exceptions are logged, never fatal

**Verification:** unit test for event→broadcast mapping (stubbed stream); manual two-browser test.

**Dependencies:** 2, 4. **Files:** `lib/remora/event_listener.rb`, Puma plugin, `config/puma.rb`, index view `turbo_stream_from`. **Scope:** M

### ✅ Checkpoint 2
- [ ] Two browsers + terminal `docker` commands: rows update live in both
- [ ] Actions round-trip through real Docker; suite green

---

## Phase 3 — Logs

### Task 6: Logs drawer (static tail)

**Description:** Clicking a row opens a full-height drawer (Turbo Frame) with the last 500 lines, stdout+stderr merged, demuxing the Docker stream-frame format (and the TTY plain-text case). Timestamps toggle; "load older" fetches further back via `until`.

**Acceptance criteria:**
- [ ] Drawer shows correct, in-order output for both TTY and non-TTY containers
- [ ] Timestamps toggle on/off; load-older extends the window

**Verification:** demux unit tests against binary fixtures (both modes); manual on a chatty container.

**Dependencies:** 2. **Files:** client log methods + demuxer, `LogsController`, drawer views, Stimulus drawer controller. **Scope:** M

### Task 7: Log search + highlighting

**Description:** Instant client-side filter over the loaded window (Stimulus, no round-trips) with match count; cheap regex visual highlighting of error/warn lines.

**Acceptance criteria:**
- [ ] Typing filters visible lines instantly and shows "n of m lines"
- [ ] error/fatal lines tinted; clearing search restores all lines

**Verification:** Stimulus controller test (or manual script); manual filter on 500-line window.

**Dependencies:** 6. **Files:** Stimulus search controller, drawer view. **Scope:** S

### Task 8: Follow mode (live tail)

**Description:** SSE endpoint (`ActionController::Live`) proxying the Engine's `follow=1` chunked stream, demuxed, one connection per open drawer. Client auto-scrolls unless the user has scrolled up. Server closes the upstream socket when the client disconnects. Raise Puma threads to 10 to budget for held connections.

**Acceptance criteria:**
- [ ] Follow on: new lines appear <1s; follow off/drawer closed: upstream Docker connection is closed (verify via lsof)
- [ ] Client disconnect never leaks the thread or the socket

**Verification:** manual with `docker run --rm alpine sh -c 'while true; do date; sleep 1; done'`; lsof check for socket cleanup.

**Dependencies:** 6. **Files:** `LogsController#follow`, client streaming method, Stimulus SSE glue, `config/puma.rb`. **Scope:** M

### ✅ Checkpoint 3
- [ ] Full log UX (tail, search, follow) works on real containers, both TTY modes
- [ ] Puma thread pool sized for streaming; suite green

---

## Phase 4 — Uptime

### Task 9: Events table + recorder

**Description:** First migration: `events` (docker_id, container_name, kind, exit_code, occurred_at, indexed on docker_id+occurred_at). The Task-5 listener also persists `start`/`die`(+exit code)/`oom`/`health_status` transitions. Nightly prune of rows >30 days (from the reconciler thread — no job framework).

**Acceptance criteria:**
- [ ] Start/stop cycles append correct rows with exit codes
- [ ] Prune deletes only rows older than 30 days

**Verification:** model + listener tests; manual: cycle a container, inspect `events` via `bin/rails db`.

**Dependencies:** 5. **Files:** migration, `Event` model, listener additions, tests. **Scope:** S

### Task 10: Uptime strip + badges

**Description:** Per-row 24h strip (green/red/grey segments) computed from `events`, rendered as inline SVG; restart count over 24h; "flapping" badge at ≥3 restarts in 10 minutes.

**Acceptance criteria:**
- [ ] Strip matches a known event sequence exactly (fixture-driven test)
- [ ] Flapping badge appears/disappears at the threshold; strip shows grey for pre-history

**Verification:** `Event.timeline_for` unit tests; visual check after forced restarts.

**Dependencies:** 9. **Files:** `Event` query methods, strip partial/helper, row partial, tests. **Scope:** M

### Task 11: Reconciler

**Description:** Second Puma-plugin thread: every 60s, list containers, compare against last recorded event per container, synthesize missing transitions (e.g. Remora was down during a crash), broadcast corrections, and run the daily prune.

**Acceptance criteria:**
- [ ] Stop a container while Remora is down → on boot, an event is synthesized and the row is correct
- [ ] Reconciler exceptions logged, never fatal

**Verification:** reconciler unit test with stubbed drift; manual kill-Remora/stop-container/restart-Remora cycle.

**Dependencies:** 9. **Files:** `lib/remora/reconciler.rb`, Puma plugin, tests. **Scope:** S

### ✅ Checkpoint 4
- [ ] Uptime strips truthful across Remora restarts and missed events
- [ ] Suite green; SQLite in `storage/` (dev) with `/data` path wired for prod

---

## Phase 5 — Launch links & Tailscale

### Task 12: Port launch chips

**Description:** Chips per published port: `http(s)://<request-host-sans-port>:<published>`, https for 443/8443. `remora.url` label replaces all derived chips; `DOCKHAND→REMORA_HOST_URL` env override supported.

**Acceptance criteria:**
- [ ] Chips derive from the browser's Host header (correct via tailnet name, LAN name, or IP)
- [ ] `remora.url` yields exactly one chip with that URL

**Verification:** presenter tests across host-header cases; manual click-through on 2+ services.

**Dependencies:** 3. **Files:** presenter link logic, row partial, tests. **Scope:** S

### Task 13: Sidecar detection + row merge

**Description:** Detect TS sidecars (image `tailscale/tailscale*` or `TS_AUTHKEY`/`TS_STATE_DIR` env) and pair app containers via `HostConfig.NetworkMode == container:<sidecar-id>`. Render pairs as one merged row: app's name, TS badge, sidecar hidden as its own row.

**Acceptance criteria:**
- [ ] A vaultwarden+ts-sidecar compose pair renders as one row with a TS badge
- [ ] Unpaired sidecars (e.g. subnet router) still render as their own row

**Verification:** presenter tests from captured inspect fixtures; manual against a real TS sidecar stack.

**Dependencies:** 2. **Files:** detection module, presenter, row partial, fixtures. **Scope:** M

### Task 14: Tailnet URLs via exec

**Description:** Run `tailscale status --json` / `tailscale serve status --json` in the sidecar via the Engine exec API; parse DNSName + served ports into `https://<dnsname>[:port]` chips on the merged row. Memoize in `Rails.cache`, invalidated by the sidecar's Docker events. Parser is fixture-driven and falls back to plain port chips on any parse failure (SPEC open question 2 resolved by graceful degradation).

**Acceptance criteria:**
- [ ] Merged row shows a working `https://<host>.<tailnet>.ts.net` chip
- [ ] Sidecar restart refreshes the cache; unparseable output degrades to port chips, never errors

**Verification:** exec + parser tests on captured JSON (current TS version); end-to-end against the real Vaultwarden stack on Guys-NAS.

**Dependencies:** 13. **Files:** client exec support, `lib/remora/tailscale.rb`, presenter, fixtures, tests. **Scope:** M

### ✅ Checkpoint 5
- [ ] On a real host: plain services launch via port chips, TS services via tailnet chips, one merged row each
- [ ] Suite green

---

## Phase 6 — Package & ship

### Task 15: Production container image

**Description:** Trim the generated Dockerfile: non-root, SQLite at `/data`, `SECRET_KEY_BASE` self-generated into `/data` on first boot (zero-config rule), container `HEALTHCHECK`, port 8080, linux/amd64+arm64 buildx.

**Acceptance criteria:**
- [ ] `docker run` block from SPEC §3 works verbatim on a clean machine
- [ ] Both architectures build; healthcheck goes healthy; survives container restart with state intact

**Verification:** local buildx build + run on the Mac; smoke the full UI against Docker Desktop from inside the container.

**Dependencies:** all prior. **Files:** `Dockerfile`, `bin/docker-entrypoint`, prod config. **Scope:** M

### Task 16: GHCR publish + install docs

**Description:** GitHub Actions workflow: buildx multi-arch push to `ghcr.io/gamcdonald123/remora` on tag. README rewritten around the two install blocks (minimal + recommended TS sidecar compose, from SPEC §3).

**Acceptance criteria:**
- [ ] Tagging `v0.1.0` publishes a public multi-arch image
- [ ] README quickstart is copy-paste sufficient on a fresh host

**Verification:** run the workflow; pull and run the published image on the Mac.

**Dependencies:** 15. **Files:** `.github/workflows/release.yml`, `README.md`, `examples/compose.yaml`, `examples/ts-serve.json`. **Scope:** S

### Task 17: Dogfood on Guys-NAS

**Description:** Deploy the published image behind its own TS sidecar on Guys-NAS (mind the 8GB RAM budget and the bind-mount quirks). Verify against the real fleet.

**Acceptance criteria:**
- [ ] Reachable at `https://remora.<tailnet>.ts.net` only; actions, logs, uptime, and tailnet chips work against the real fleet
- [ ] RSS < 250MB steady-state after 24h (SPEC §8 budget)

**Verification:** `docker stats` after 24h; click through every feature against real containers (incl. the Vaultwarden TS pair).

**Dependencies:** 16. **Files:** none in-repo (NAS compose). **Scope:** S

### ✅ Checkpoint 6 — v1 done
- [ ] All SPEC §2 "In" items demonstrable on Guys-NAS
- [ ] Memory budget met; repo README accurate; `v0.1.0` tagged

---

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Docker log multiplexing (TTY vs non-TTY frames) corrupts output | Med | Dedicated demuxer with binary fixtures for both modes (Task 6) |
| Broadcasting from background threads breaks with async cable adapter | High | It's Task 5 — earliest possible slot; fallback is a 5s polling refresh (degraded but shippable) |
| Each follow-mode viewer holds a Puma thread | Med | Threads→10, one SSE per client, close upstream on disconnect (Task 8) |
| `tailscale serve status --json` output varies across TS versions | Med | Fixture-driven parser + graceful fallback to port chips (Task 14) |
| Dev on macOS vs prod on Linux NAS | Low | Docker Desktop socket is API-identical; NAS validation at Checkpoints 5–6 |
| RSS blows the 250MB budget on the NAS | Med | jemalloc+YJIT already in image; measure at Checkpoint 6 before calling v1 done |

## Parallelization

Safe to run concurrently once Checkpoint 1 passes: Phase 3 (logs) ⊥ Phase 4 (uptime) ⊥ Task 12 (port chips). Tasks 13–14 (Tailscale) and Phase 6 are sequential chains.

## Open questions (for review)

1. OK to drop the `containers` and `exec_cache` tables from SPEC §8 in favor of direct rendering + `Rails.cache`? (Recommended; spec would be amended.)
2. Task 8 sets Puma threads to 10 — acceptable trade for streaming, or cap follow-mode viewers instead?
