# IPv4 internet exceptions

The default configuration has no internet exceptions. Add exact domain names
with `list allowed_domain` or individual internet IPv4 addresses with
`list allowed_ip` in `/etc/config/swfence`, or use the corresponding LuCI lists.
At most 32 domains and 64 addresses are accepted, within the configuration field
size limits. Wildcards, URLs, CIDRs, IPv6, private/local IPv4 destinations and
reserved connection-check/diagnostic names are rejected.

Manual IP exceptions are rendered as literal destination sets in each guard
chain. Domain exceptions use separate timeout sets in `inet fw4` and
`bridge swfence`. Other router services remain blocked before the exception
rules. Allowing a destination returns control to existing OpenWrt policy;
it does not bypass a separate forwarding restriction.

The supervised worker queries only applied, validated domain names, using A
lookups against the applied router address on the normal DNS port. It ignores
the DNS server header, non-IPv4 answers and private/local addresses. Only exact
configured names and their validated A answers are written to the RAM hosts
file consumed by the isolated DNS instance. CNAME dependencies do not create
additional permitted DNS names. Add required subdomains separately.

Lookups run outside the apply lock. Before committing, the worker acquires the
same lock as firewall apply and compares its configuration snapshot to the
current applied settings. An nftables transaction replaces both dynamic sets
before new DNS answers are advertised. SIGHUP reloads only the isolated DNS
instance's hosts file. The worker sleeps 60 seconds between refreshes. Dynamic
permissions expire after 180 seconds without refresh; manual IP exceptions
remain until removed. Lookup failures omit the affected domain; failed nft
transactions retain the preceding DNS file and report an error. Remaining
dynamic entries still expire. Current status distinguishes waiting, successful
resolution counts, expiration and refresh errors.

Firewall reloads clear dynamic memberships. In particular, fw4's table flush
preserves named sets, so the post-table include explicitly flushes the domain
sets in both families. Manual exceptions use literal rules so removed addresses
cannot survive in a persistent named set. Dynamic access resumes after the next
successful refresh, potentially after the current 60-second pause.

An IP-based guard cannot distinguish HTTPS hostnames sharing one address. A
permitted proxy or VPN endpoint can relay traffic. Console-to-WAN checks on
actual hardware remain required; router-local DNS success is not that proof.

The DNS reload behavior follows the [dnsmasq manual](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html).
