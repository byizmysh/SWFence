# SWFence

**Keep it local.** OpenWrt firewall protection for Nintendo Switch and Nintendo Switch 2, with a minimal LuCI panel.

> [!CAUTION]
> ❗ **Use SWFence at your own risk.** Back up your router configuration and verify protection on your own hardware. Internet isolation and protection from console/account bans are not guaranteed.

SWFence keeps selected IPv4 LAN services accessible while blocking other console traffic by MAC address. It is a router-side replacement for **90DNS when your goal is local access without general internet access**. It blocks direct-IP traffic too, so it does not need a list of every Nintendo server. Optional exact-domain and individual IPv4 exceptions let you open specific internet destinations. IPv6 remains blocked.

**Release:** [v0.3.0](https://github.com/byizmysh/SWFence/releases/tag/v0.3.0) · [Download the install bundle](https://github.com/byizmysh/SWFence/releases/download/v0.3.0/swfence-0.3.0.tar.gz) · [Installation instructions](INSTALL.md)

**Validation:** automated userspace, LuCI view and isolated packet tests pass. Real-router installation, reboot behavior, actual LuCI/rpcd operation and physical Switch model compatibility still require hardware testing.

## What you can do

- Register the console's Wi-Fi MAC and each dock/Ethernet adapter MAC.
- Keep a selected private IPv4 subnet accessible, or allow one local TCP service.
- Block external IPv4, external DNS and all IPv6 for the listed MACs.
- Optionally allow exact domain names or individual internet IPv4 addresses.
- Apply settings in LuCI with progress, router confirmation and clear error messages.
- Watch today's dropped-packet totals and live changes, with the router timezone displayed.
- Run repeating local diagnostics and roll back the previous successful configuration.

Protection applies only to the registered MACs through this OpenWrt router. Other devices and the router's own internet access are not restricted by SWFence.

## Requirements

- OpenWrt **24.10.x** with opkg, or **25.12.x** with apk, using firewall4/nftables.
- SSH root access and internet access on the router for downloading packages/dependencies.
- LuCI for the web panel; automatic fw4 includes and the firmware's `kmod-nft-bridge` package.
- The router must see the console's original MAC. A downstream router performing NAT hides it.

The packages contain shell scripts and JavaScript (`all`/`noarch`). Runtime/kernel dependencies are installed from the router's own firmware feeds. The release packages were built with official OpenWrt 24.10.4 and 25.12.2 SDKs.

> [!WARNING]
> ❗ **Nonstandard zones, VLANs, acceleration or proxy routing require device-specific validation.** Use SWFence at your own risk and verify protection on your router.

## Install with the SSH script

> [!CAUTION]
> ❗ **Before installation: disable traffic acceleration.** In LuCI, open **Network → Firewall** and disable **Software flow offloading** and **Hardware flow offloading**. On manufacturer firmware, also check **Network Acceleration / NAT acceleration**. SWFence does not disable these settings automatically; protection with acceleration enabled has not been verified.
>
> Keep the console disconnected from the internet until protection is applied and checked. After changing firewall, VPN, proxy or acceleration modules, check isolation again, including after a router reboot. A correct MAC alone does not prove isolation.

**Before the console's first connection:** keep its Wi-Fi disconnected and Ethernet unplugged while installing and configuring SWFence. The router needs internet access for installation; the console does not. Protection is disabled by default, and entering a MAC alone does not activate it.

Use your actual router LAN address in place of `192.168.1.1`.

**1. Connect from your computer:**

```sh
ssh root@192.168.1.1
```

**2. Run these commands on the OpenWrt router:**

```sh
wget -O /tmp/swfence-install.sh https://github.com/byizmysh/SWFence/releases/download/v0.3.0/install.sh
sh /tmp/swfence-install.sh byizmysh/SWFence v0.3.0
```

The installer checks the firmware family, downloads its two native packages, verifies the selected files against the release SHA256SUMS, installs dependencies and opens the setup wizard. It does not guess the console's MAC. The checksum manifest comes from the same GitHub release; use the repository you trust. OpenWrt 25.12 uses `--allow-untrusted` only for the two local release APKs after checksum verification; they are not signed by the OpenWrt project.

**3. Complete setup:** enter your actual Wi-Fi/Ethernet MACs, this OpenWrt router's LAN IPv4, and the allowed local subnet. Defaults are detected from the `lan` interface where possible; check them. The wizard enables and applies protection: check that it reports success. If configuring in LuCI instead, explicitly enable protection and apply. The bundled example MACs cannot be enabled. Keep the console disconnected.

**4. Check the router:** open **LuCI → Services → SWFence** (sign in again if needed). For complete external blocking, verify that both internet-exception lists are empty. Check that protection is enabled, settings are applied and both firewall guards are loaded; run local diagnostics. Resolve any errors before connecting the console.

**5. Connect the console:** leave **IP Address Settings → Automatic** if using DHCP. Set **DNS Settings → Manual** and enter the OpenWrt router's LAN IPv4 in **both DNS fields**, replacing old 90DNS addresses. Disable console proxy settings, then connect. Verify local access and blocked external traffic from the console. A successful basic connection check alone does not prove internet isolation.

**Router fields versus console DNS:** **Router LAN IPv4** and **Allowed IPv4 subnet** are SWFence settings on the router; do not enter the subnet as the console's address. Once the MAC guard is active, it blocks unapproved external traffic independently of console DNS. Keeping old 90DNS addresses or automatic DNS does not bypass the guard, but external DNS is blocked by default. Use the router's LAN IPv4 for SWFence's local DNS/connection-check responses. Automatic DNS is suitable only if DHCP supplies that same router DNS address.

Download the [release archive](https://github.com/byizmysh/SWFence/releases/download/v0.3.0/swfence-0.3.0.tar.gz) for the installer, native packages and English installation instructions. See [INSTALL.md](INSTALL.md) for archive/manual installation and [all release files](https://github.com/byizmysh/SWFence/releases/tag/v0.3.0).

## Find your addresses

**Wi-Fi MAC:** on the console, open HOME → System Settings → Internet → System MAC Address. [Nintendo instructions](https://en-americas-support.nintendo.com/app/answers/detail/a_id/22397/p/897).

**Ethernet MAC:** use the actual dock/USB adapter's MAC. Check wired connection details, the adapter label or OpenWrt DHCP leases (`/tmp/dhcp.leases`). Replacing an adapter may require a new entry. Hostnames alone are not reliable identification. If you must connect an unprotected console to discover its MAC, install the packages first, then physically disconnect the router's WAN and any backup internet uplinks. Identify its lease on the LAN, enable/apply protection and check the guards, then restore WAN. The console must have no alternative internet connection during discovery.

**Router LAN IPv4:** the local address of this OpenWrt router, often the IPv4 used to open LuCI, such as `192.168.1.1`. In a multi-router network, the default gateway may belong to a different router; select the OpenWrt instance running SWFence.

**Allowed IPv4 subnet:** local destinations the console may reach. For a home LAN using `192.168.1.x`, a typical subnet is `192.168.1.0/24`. Use the actual subnet from your router. A strict profile instead leaves this field empty and sets a local host IPv4 plus one TCP port; that profile also restricts replies to incoming LAN connections.

## What the firewall allows

| Traffic from a registered console MAC | Policy |
| --- | --- |
| Selected private IPv4 subnet or strict local TCP service | Allowed by SWFence; existing router policies still apply |
| DHCP, isolated DNS and basic local connection check | Allowed |
| Other router services/proxy ports | Blocked |
| Explicit internet IPv4/domain exceptions | Allowed by SWFence; existing router policies still apply |
| Other external IPv4 and external DNS | Blocked |
| All IPv6, including local IPv6 | Blocked |

The dedicated DNS maps `ctest.cdn.nintendo.net` and supported Switch 2 connection-check names to the router. A local HTTP service returns the expected basic reply. Those names are **not external firewall exceptions**. General internet, online play, eShop, updates and full speed/NAT checks are unavailable by default. Local DNS names, mDNS and multicast discovery are not provided; use local IPv4 addresses.

## Optional internet exceptions

Add entries in **Allowed internet domains** or **Allowed internet IPv4 addresses**, then apply. Leave both lists empty for the default LAN-only policy.

- Domains are exact ASCII names, such as `example.com`. Add required subdomains such as `api.example.com` separately. Use Punycode for international names. URLs, paths, wildcards and ports are not accepted.
- IP exceptions are individual internet IPv4 addresses, such as `1.1.1.1`, with no subnet mask. All ports/protocols to that address are permitted. IPv6 remains blocked.
- A background worker resolves configured names through normal router DNS, advertises validated A answers only for those exact names, and pauses 60 seconds between refreshes. Unresolved names stay blocked. Dynamic permissions expire after 180 seconds without refresh. A firewall reload clears them until the next successful refresh.

A domain exception permits its destination IP, which may also serve other sites. An allowed proxy/VPN endpoint can relay traffic. The panel reports waiting, resolved/unresolved, expired and failed refresh states. See [implementation details](docs/internet-exceptions.md).

## CLI, updates and removal

```sh
swfence status
swfence diagnostics
swfence setup
swfence reload
swfence rollback
```

Settings are stored in `/etc/config/swfence`: `list mac`, `router_ip`, `lan_subnet`, optional `local_host`/`local_port`, `list allowed_domain` and `list allowed_ip`. A rollback can restore a disabled configuration, so check the resulting status.

For a future release, run that release's installer using its exact version tag. Updates can interrupt connections when firewall rules reload. Configuration and generated rules are included in sysupgrade preservation, but packages must be reinstalled and revalidated after a firmware upgrade. An old private `ns2` guard is detected rather than silently overwritten.

To remove protection, turn it off in LuCI and apply. Merely stopping the local DNS/HTTP service intentionally leaves the guard loaded. Removing the packages explicitly removes protection and can restore internet access:

```sh
# OpenWrt 24.10.x
opkg remove luci-app-swfence swfence

# OpenWrt 25.12.x
apk del luci-app-swfence swfence
```

## Limits and validation

SWFence checks console traffic in early bridge/inet prerouting chains at priority `-310`. An ordinary allow rule cannot override its final drop. It does not have exclusive control of the router: another privileged module can remove or replace rules, change packet handling before these checks, or provide an accelerated path. Recheck isolation after network/firewall changes.

Allowed LAN hosts and internet exceptions must be trusted: they can relay traffic outward. Other Wi-Fi networks, hotspots, unregistered adapters, downstream NAT and nonstandard acceleration are outside the verified test scope. No console/account ban-prevention guarantee is made.

The project has **23 core tests**, LuCI view tests for state/feedback/errors, and isolated nftables packet tests for allowed traffic, blocked traffic, exception expiry/revocation and rule reload. Real hardware acceptance is still outstanding; see [testing](docs/testing.md).

## Build and contribute

```sh
python3 tests/test_core.py
node tests/test_panel.cjs
sh scripts/build-sdk.sh /path/to/openwrt-sdk
python3 scripts/build-release.py
```

The recipes are in `packages/`. CI runs tests; native-package builds and release preparation are manually triggered. [Architecture](docs/architecture.md) · [Release preparation](docs/publishing.md) · [Contributing](CONTRIBUTING.md).

MIT licensed. See [LICENSE](LICENSE).
