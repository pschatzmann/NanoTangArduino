#!/usr/bin/env bash
# Copies the subset of ArduinoCore-API/api/ this core actually compiles into
# cores/tangnano20k/api/. We don't use the submodule's api/ folder directly
# as a build source: arduino-cli recursively compiles every .c/.cpp/.S under
# the core directory, and the submodule root also carries a test/ tree
# (Catch2 unit tests) that isn't meant to be compiled by a sketch build.
#
# All headers are copied (harmless if unused - Print.h etc. reference
# String/IPAddress/etc. only by declaration). Only the .cpp files this v1
# core actually links against are copied: Common.cpp, Print.cpp, Stream.cpp.
# String.cpp/IPAddress.cpp/CanMsg*.cpp/PluggableUSB.cpp need malloc/USB
# support this bare-metal core doesn't provide yet, so their headers are
# available (for API completeness / future use) but their implementations
# are intentionally left out of the build.
#
# Run this again after updating the ArduinoCore-API submodule.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/ArduinoCore-API/api"
DST="$ROOT/cores/tangnano20k/api"

rm -rf "$DST"
mkdir -p "$DST"

# All headers, recursively (includes deprecated/ and deprecated-avr-comp/).
(cd "$SRC" && find . -name '*.h' -print0) | while IFS= read -r -d '' f; do
  mkdir -p "$DST/$(dirname "$f")"
  cp "$SRC/$f" "$DST/$f"
done

# Only the .cpp files this core links against.
for f in Common.cpp Print.cpp Stream.cpp; do
  cp "$SRC/$f" "$DST/$f"
done

echo "Vendored ArduinoCore-API headers + {Common,Print,Stream}.cpp into $DST"
