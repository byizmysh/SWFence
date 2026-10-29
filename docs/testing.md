# Testing SWFence

The LuCI diagnostics button runs router-local checks only:

| Check | What it shows |
| --- | --- |
| Configuration | Valid real MACs and private destinations |
| Firewall syntax | `fw4 check` accepts installed rules |
| Hooks | Both inet and bridge guard chains exist |
| Applied settings | Saved settings match the last successful apply |
| DNS configuration | Isolated dnsmasq configuration parses |
| DNS connection-check A | Answer is the applied router IPv4 |
| External A and AAAA queries | Local resolver returns NXDOMAIN |
| Local HTTP | Fixed connection-check response has the expected body |
| Console external isolation | ON CONSOLE in LuCI; `manual` in the CLI JSON |

The panel never equates these checks with proof of console isolation. Green
local checks cannot establish behavior on another network, an unlisted adapter,
a downstream NAT router, hardware acceleration, or a trusted LAN proxy.
The kernel counters are aggregate per path and reset on firewall reload. The
panel instead shows sampled totals for the current day in the router timezone.
A procd collector samples every 5 seconds without requiring an open browser;
status requests also update the shared sample. At the first observation of a
new day the collector establishes a fresh baseline. The boundary can omit up
to one sampling interval of traffic. Observed kernel-counter decreases preserve
the accumulated daily total and add the new counter value. A reset and subsequent
increase between samples cannot always be distinguished from a normal increase;
traffic between the last sample and a rules reset can be lost.
RAM storage survives service restarts but not router reboots. The actual
collection start time is displayed; earlier traffic is never backfilled.
CLI `counters` retains the raw kernel values; `daily_counters` holds the daily
totals, router date/timezone, collection start and last sample timestamp.
Status and the panel's daily counter changes refresh every 5 seconds.
After a failed status request, the next successful sample establishes a fresh
baseline. Starting live diagnostics enables a 15-second refresh until stopped
or the page is closed. Failed checks replace previous results with an error;
overlapping requests share the pending diagnostic request.

Internet exception coverage includes exact-name DNS answers and removal after SIGHUP, validation, settings compatibility, rejected private DNS answers, DNS/nft failures, settings changes during lookup, and both nftables paths. Packet tests verify explicit exceptions, dynamic membership expiry, revocation, and removal of manual exceptions after rules reload.

## Automated checks

### Initial release validation

The local preparation of version 0.3.0 passed all 23 core tests with the
checksum-verified OpenWrt 24.10.4 rootfs, the LuCI view tests, and the isolated
kernel packet tests described below. Native packages were built with the
official OpenWrt 24.10.4 and 25.12.2 SDKs: two architecture-independent IPKs
(`all`) and two APKs (`noarch`). Package metadata and the bundled LuCI view
were inspected. The browser preview uses simulated data.

These results cover the test environments only. The hardware acceptance
checks below remain outstanding.

```sh
python3 tests/test_core.py
node tests/test_panel.cjs
```

The live DNS unit test requires host dnsmasq and loopback sockets. Native tests
are skipped unless `SWFENCE_ROOTFS` names a checksum-verified x86 OpenWrt rootfs:

```sh
SWFENCE_ROOTFS=/path/to/rootfs python3 tests/test_core.py
unshare -Urn python3 tests/kernel_probe.py
```

Native tests use real OpenWrt ash/UCI/jshn/jsonfilter/dnsmasq, with controlled
fw4/nft/procd replacements to inject failures. Kernel tests separately load
real nftables rules, inject synthetic frames on virtual interfaces, and inspect
verdict counters for LAN, outside IPv4, outside DNS, IPv6, router proxy ports,
other MACs and the strict TCP profile. The kernel test refuses to run unless
its network namespace initially contains only loopback. It never uses WAN or
the physical network.

## Hardware acceptance before a stable release

1. Use a disposable configuration or backup on a supported OpenWrt router.
2. Configure each actual console Wi-Fi/Ethernet MAC; verify the corresponding
   DHCP lease, IPv4 LAN communication and both DNS settings on the console.
3. Confirm external IPv4 and IPv6 attempts increase the appropriate drop
   counters. If inspecting WAN, correlate source/translated traffic carefully.
4. Verify router proxy ports are blocked, and ordinary devices are unaffected.
5. Reload firewall, reboot router, and repeat. Exercise installation, upgrade,
   disable, previous-config rollback and package removal.
6. Verify the LuCI app in the actual installed LuCI release and a read-only
   account. Test local DNS and HTTP failure states separately.
7. Repeat for Switch 1 / Lite / OLED and Switch 2 before listing any real-device
   model or firmware as hardware-verified.

These manual hardware, real LuCI/rpcd, SSH-from-GitHub and reboot checks have
not been performed as part of this initial preparation.
