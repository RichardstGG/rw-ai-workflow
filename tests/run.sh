#!/usr/bin/env bash
# usage: tests/run.sh -- runs every tests/*.test.sh; exit 1 if any fails
cd "$(dirname "$0")"; rc=0
for t in *.test.sh; do echo "# $t"; bash "$t" || rc=1; done
exit $rc
