# Contributing

Keep changes focused and include a reproducible description of the behavior.
Never attach router credentials, device MACs, WAN captures containing private data,
or unredacted production configuration to an issue.

Run `python3 -m unittest discover -s tests -v` and `node tests/test_panel.cjs`.
The host DNS test requires dnsmasq and loopback UDP sockets. Optional native tests
require a checksum-verified OpenWrt rootfs, `unshare` and `chroot`:

```sh
SWFENCE_ROOTFS=/path/to/extracted/rootfs python3 -m unittest discover -s tests -v
```

Native transaction tests run the real OpenWrt ash, UCI, jsonfilter and jshn,
with controlled replacements for fw4, nft and procd. Kernel packet tests are
separate and never use the physical network. See `docs/testing.md`.

Use `sh scripts/build-sdk.sh /path/to/sdk` for native packages. Do not change
status wording to imply that loaded rules or local DNS tests certify console
isolation. Keep RPC permissions limited to the application methods.
