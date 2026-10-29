# Changelog

## 0.3.0 — Unreleased

- Introduce the SWFence name and native `swfence` / `luci-app-swfence` packages.
- Add a minimal native LuCI panel under Services with settings, live status, drop counters and local diagnostics; no custom UI colors or stylesheet.
- Use narrowly scoped rpcd methods instead of general file/shell access from the panel.
- Add UCI configuration, transactional firewall apply, previous-config rollback and procd services.
- Keep firewall restrictions loaded if the local connection-check service stops.
- Add an SSH-first GitHub release installer and router setup wizard.
- Preserve support for both connection-check hostnames; Switch 1 hardware compatibility remains unverified.
- Ship English documentation, tests, SDK build instructions and manual release workflows.
- Live status timestamps and counter changes; start/stop automatic local diagnostics every 15 seconds. Console verification is labeled ON CONSOLE.
- Count observed drops for the current router-local day with background RAM statistics, a midnight rollover, and visible collection start time.
- Add optional exact-domain and individual IPv4 internet exceptions, background resolution, expiring permissions and resolution status.
- Add a bold SWFence page heading and a repository footer link supplied at publication or by the GitHub installer.
- Show apply/verification progress, persistent confirmed/error feedback, unsaved edits and duplicate-click protection in LuCI.
