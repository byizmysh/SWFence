#!/bin/sh
# Shared validation for public IPv4 exceptions and exact ASCII DNS names.
internet_ipv4() {
    printf '%s\n' "$1" | awk -F. '
      NF!=4 {exit 1}
      {for(i=1;i<=4;i++) if($i !~ /^(0|[1-9][0-9]*)$/ || $i>255) exit 1}
      {exit ($1==0 || $1==10 || $1==127 || $1>=224 ||
             ($1==169 && $2==254) || ($1==172 && $2>=16 && $2<=31) ||
             ($1==192 && $2==168) || ($1==100 && $2>=64 && $2<=127))}'
}
exact_domain() {
    printf '%s\n' "$1" | awk '
      length>253 || !/\./ || /[^a-zA-Z0-9.-]/ {exit 1}
      {n=split($0,a,"."); for(i=1;i<=n;i++) if(length(a[i])<1 || length(a[i])>63 || a[i] ~ /^-/ || a[i] ~ /-$/) exit 1;
       if(a[n] !~ /[a-zA-Z]/) exit 1}'
}
validate_exceptions() {
    local value count=0
    for value in $ALLOWED_IPS; do
        count=$((count+1))
        [ "$count" -le 64 ] && internet_ipv4 "$value" || { echo 'Use at most 64 individual internet IPv4 addresses; no URLs, ranges or local addresses.' >&2; return 1; }
    done
    count=0
    for value in $ALLOWED_DOMAINS; do
        count=$((count+1))
        [ "$count" -le 32 ] && exact_domain "$value" || { echo 'Use at most 32 exact ASCII domain names; no URLs, wildcards or ports.' >&2; return 1; }
        case "$(printf '%s' "$value" | tr 'A-Z' 'a-z')" in
            ctest.cdn.nintendo.net|ctest.p01.ctest.srv.nintendo.net|ctest-ipv6.p01.ctest.srv.nintendo.net|conntest.nintendowifi.net|swfence-unlisted.invalid)
                echo 'Connection-check and diagnostic names are reserved for local responses.' >&2; return 1 ;;
        esac
    done
}
