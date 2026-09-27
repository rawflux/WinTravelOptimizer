#!/bin/sh
# Builds bin/WinTravelOptimizer-<version>.zip (script, launcher, README.txt, LICENSE with CRLF) and SHA256SUMS.
set -e
cd "$(dirname "$0")"
ver=$(sed -n "s/^\$Version = '\(.*\)'/\1/p" WinTravelOptimizer.ps1)
[ -n "$ver" ] || { echo "cannot read \$Version" >&2; exit 1; }
out=bin/WinTravelOptimizer-$ver
rm -rf bin && mkdir -p "$out"
for f in WinTravelOptimizer.ps1 Start-WinTravelOptimizer.cmd README.txt LICENSE; do sed 's/\r*$/\r/' "$f" > "$out/$f"; done
(cd bin && zip -qr "WinTravelOptimizer-$ver.zip" "WinTravelOptimizer-$ver")
(cd bin && sha256sum "WinTravelOptimizer-$ver.zip" > SHA256SUMS)
ls -l bin/*.zip bin/SHA256SUMS
