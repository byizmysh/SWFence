#!/bin/sh
# Sourced after common.sh. Keep sampled daily totals in RAM, never router flash.
count_drops() {
    nft list chain "$1" "$2" "$3" 2>/dev/null | awk '/counter packets/ && / drop/ {for(i=1;i<=NF;i++) if($i=="packets") n+=$(i+1)} END {printf "%.0f", n+0}'
}

sample_statistics() (
    local bridge=$1 inet=$2 day now old_day since updated old_bridge old_inet total_bridge total_inet
    day=$(date +%F)
    now=$(date +%s)
    mkdir -p "$RUN"
    # Status requests and the background collector share this lock and baseline.
    mkdir "$RUN/statistics.lock" 2>/dev/null || return 0
    trap 'rm -f "$RUN/statistics.tmp"; rmdir "$RUN/statistics.lock" 2>/dev/null || true' EXIT
    trap 'exit 1' HUP INT TERM
    old_day= since= updated= old_bridge= old_inet= total_bridge= total_inet=
    if [ -f "$RUN/statistics" ]; then
        read -r old_day since updated old_bridge old_inet total_bridge total_inet < "$RUN/statistics" || true
    fi
    if [ "$old_day" = "$day" ] && printf '%s\n' "$since $updated $old_bridge $old_inet $total_bridge $total_inet" | grep -Eq '^[0-9]+( [0-9]+){5}$'; then
        # A decreasing kernel counter means rules were reset. Preserve the daily
        # total and add the newly observed packets on each path independently.
        total_bridge=$(awk -v total="$total_bridge" -v old="$old_bridge" -v value="$bridge" 'BEGIN {printf "%.0f",total+(value>=old ? value-old : value)}')
        total_inet=$(awk -v total="$total_inet" -v old="$old_inet" -v value="$inet" 'BEGIN {printf "%.0f",total+(value>=old ? value-old : value)}')
    else
        # First observation or a new router-local day: establish a baseline.
        # Never attribute an unobserved, possibly multi-day kernel total to today.
        since=$now
        total_bridge=0
        total_inet=0
    fi
    if (umask 077; printf '%s %s %s %s %s %s %s\n' "$day" "$since" "$now" "$bridge" "$inet" "$total_bridge" "$total_inet" > "$RUN/statistics.tmp"); then
        mv "$RUN/statistics.tmp" "$RUN/statistics"
    fi
)

read_statistics() {
    STAT_DAY=$(date +%F)
    STAT_ZONE=$(date '+%Z %z')
    STAT_AVAILABLE=0 STAT_SINCE=0 STAT_UPDATED=0 STAT_BRIDGE=0 STAT_INET=0 STAT_SINCE_LOCAL=
    local day since updated bridge inet total_bridge total_inet
    if [ -f "$RUN/statistics" ]; then
        read -r day since updated bridge inet total_bridge total_inet < "$RUN/statistics" || return 0
        if [ "$day" = "$STAT_DAY" ] && printf '%s\n' "$since $updated $bridge $inet $total_bridge $total_inet" | grep -Eq '^[0-9]+( [0-9]+){5}$'; then
            STAT_AVAILABLE=1 STAT_SINCE=$since STAT_UPDATED=$updated
            STAT_BRIDGE=$total_bridge STAT_INET=$total_inet
            STAT_SINCE_LOCAL=$(date -d "@$since" '+%Y-%m-%d %H:%M:%S %Z')
        fi
    fi
}
