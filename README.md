# Remora 🐟

**A single-container, zero-configuration Docker dashboard — with first-class awareness of Tailscale sidecars.**

Install it on any host and immediately see, control, launch, and monitor every container on that machine. No config files, no onboarding, no accounts. Everything it shows is discovered, not configured.

> A remora is the fish that attaches itself to a larger host and rides along — the original sidecar.

## Status

Pre-alpha — currently a [specification](SPEC.md) and an empty harbor. Built with Rails 8, Hotwire, and SQLite.

## Principles

1. **Zero configuration** — populated the moment it starts; tunables are Docker labels, never a settings UI.
2. **One screen** — the container list *is* the app.
3. **The tailnet is the auth layer** — designed to run behind its own Tailscale sidecar, never exposed to LAN or internet.
4. **Turnkey** — one paste-able compose block.

See [SPEC.md](SPEC.md) for the full v1 specification.

## License

MIT
