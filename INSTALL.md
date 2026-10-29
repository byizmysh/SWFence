# Installing SWFence 0.3.0

This release supports OpenWrt 24.10.x (opkg) and 25.12.x (apk) with firewall4. Actual router/console hardware acceptance remains outstanding. The OpenWrt router itself needs internet access for installation; SWFence restricts only configured console MACs.

## Recommended: SSH installer

> [!CAUTION]
> ❗ **Before installation: disable traffic acceleration.** In LuCI, open **Network → Firewall** and disable **Software flow offloading** and **Hardware flow offloading**. On manufacturer firmware, also check **Network Acceleration / NAT acceleration**. SWFence does not disable these settings automatically; protection with acceleration enabled has not been verified.
>
> Keep the console disconnected from the internet until protection is applied and checked. After changing firewall, VPN, proxy or acceleration modules, check isolation again, including after a router reboot. A correct MAC alone does not prove isolation.

**Before any installation method:** keep the console's Wi-Fi disconnected and Ethernet unplugged. The router needs internet access for package downloads; the console does not. Protection is disabled by default. Do not connect the console until its actual MACs are configured, protection is enabled/applied and the router checks pass.

From your computer, connect using your router's actual LAN address:

```sh
ssh root@192.168.1.1
```

Then run on OpenWrt:

```sh
wget -O /tmp/swfence-install.sh https://github.com/byizmysh/SWFence/releases/download/v0.3.0/install.sh
sh /tmp/swfence-install.sh byizmysh/SWFence v0.3.0
```

The script downloads the matching native packages and verifies their release checksums before installation. Complete the Wi-Fi/Ethernet MAC, router LAN IPv4 and allowed-subnet wizard; check that enabling/applying protection succeeds. While the console is still disconnected, open LuCI → Services → SWFence, check the applied settings and both firewall guards, leave both internet-exception lists empty for complete external blocking, and run diagnostics. Then set both console DNS addresses manually to that router LAN IPv4, leave console IP addressing automatic if using DHCP, disable console proxy settings and connect. Verify allowed/blocked traffic from the console.

## If you downloaded the archive

`swfence-0.3.0.tar.gz` contains this file, the English README, `install.sh`, all four native package files, VERSION, LICENSE and checksums. It contains no screenshots or router-specific credentials/configuration. Extract it on your computer or OpenWrt:

```sh
tar -xzf swfence-0.3.0.tar.gz
cd SWFence
```

You can run the included online installer on OpenWrt:

```sh
sh install.sh byizmysh/SWFence v0.3.0
```

It fetches and verifies packages from the GitHub release, even if package files are already present in the extracted directory.

Alternatively, copy the entire extracted SWFence directory to the router. From the extracted directory on OpenWrt, verify the bundle and install the pair for your firmware:

```sh
sha256sum -c SHA256SUMS
```

On **OpenWrt 24.10.x**:

```sh
opkg update
opkg install ./swfence-24.10.ipk ./luci-app-swfence-24.10.ipk
swfence setup
```

On **OpenWrt 25.12.x**:

```sh
apk update
apk add --allow-untrusted ./swfence-25.12.apk ./luci-app-swfence-25.12.apk
swfence setup
```

Run only the package-manager commands for your firmware family. The APKs are local unsigned packages; use `--allow-untrusted` only after verifying these downloaded files. Dependencies still come from your router's firmware feeds.

## Before connecting the console

Router LAN IPv4 and Allowed IPv4 subnet are settings on the router, not static IP settings for the console. Active MAC firewall rules block unapproved external traffic independently of console DNS; old 90DNS addresses cannot bypass them. Manual DNS pointing to the OpenWrt router provides SWFence's local replies. Automatic DNS is suitable only if DHCP supplies that same router DNS address.

If discovering an Ethernet MAC requires connecting an unprotected console, install the packages first, physically disconnect WAN and all backup internet uplinks, identify the console's LAN lease, then enable/apply protection and check the guards before restoring WAN. Keep the console disconnected from all other internet connections.

## After installation

- Replace random example MACs with the console's actual Wi-Fi and dock/adapter MACs.
- Router LAN IPv4 is the local address of the OpenWrt instance running SWFence, not its WAN address.
- Allowed IPv4 subnet is the trusted local range, for example `192.168.1.0/24` for a LAN using `192.168.1.x`.
- Leave both internet-exception lists empty to block general internet access. Explicit domains/IPs open only their validated IPv4 destinations; IPv6 remains blocked.
- The basic console connection check is answered locally. Its success does not certify internet isolation.

Full usage and limits: https://github.com/byizmysh/SWFence#readme
