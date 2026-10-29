#!/bin/sh
set -eu
. "${SWFENCE_ROOT:-}/usr/lib/swfence/common.sh"
. "$LIB/statistics.sh"
while :; do
    sample_statistics "$(count_drops bridge swfence console)" "$(count_drops inet fw4 swfence_policy)"
    sleep 5
done
