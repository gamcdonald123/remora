# Remora v1 — Task Checklist

Details, acceptance criteria, and verification steps: [plan.md](plan.md).

## Phase 1 — See
- [x] 1. Docker socket client (`Remora::Docker`, Excon) — S
- [x] 2. Fleet view page (grouped container list, self-hide) — M
- [x] 3. Label handling (`remora.hide`, `remora.name`) — XS
- [x] **Checkpoint 1:** real fleet renders; suite green

## Phase 2 — Control
- [x] 4. Start / stop / restart actions (confirm, toasts, Turbo row refresh) — M
- [x] 5. Events listener thread → live row broadcasts ⚠ highest risk — M
- [x] **Checkpoint 2:** two-browser live updates from terminal docker commands

## Phase 3 — Logs
- [x] 6. Logs drawer, static tail + demuxer (TTY & non-TTY) — M
- [x] 7. Client-side search + error highlighting — S
- [x] 8. Follow mode (SSE proxy, thread budget) — M
- [x] **Checkpoint 3:** full log UX on real containers

## Phase 4 — Uptime
- [x] 9. `events` table + recorder + 30d prune — S
- [x] 10. 24h uptime strip + restart/flapping badges — M
- [x] 11. Reconciler thread (heal missed events) — S
- [x] **Checkpoint 4:** strips truthful across Remora restarts

## Phase 5 — Links & Tailscale
- [ ] 12. Port launch chips (Host-header derived, `remora.url`) — S
- [ ] 13. TS sidecar detection + merged rows — M
- [ ] 14. Tailnet URL chips via exec (`tailscale status/serve`) — M
- [ ] **Checkpoint 5:** tailnet chip works on a real TS stack

## Phase 6 — Package & ship
- [ ] 15. Production image (non-root, /data, self-managed secret, multi-arch) — M
- [ ] 16. GHCR release workflow + install docs — S
- [ ] 17. Dogfood on Guys-NAS; RSS < 250MB after 24h — S
- [ ] **Checkpoint 6:** v0.1.0 tagged, all SPEC §2 features live on the NAS

Parallelizable after Checkpoint 1: Phase 3 ⊥ Phase 4 ⊥ Task 12.
