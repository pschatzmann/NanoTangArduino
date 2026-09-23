#!/usr/bin/env bash
# Copies the subset of ArduinoCore-API/api/ this core actually compiles into
# cores/tangnano20k/api/. We don't use the submodule's api/ folder directly
# as a build source: arduino-cli recursively compiles every .c/.cpp/.S under
# the core directory, and the submodule root also carries a test/ tree
# (Catch2 unit tests) that isn't meant to be compiled by a sketch build.
#
# All headers are copied (harmless if unused - Print.h etc. reference
# String/IPAddress/etc. only by declaration). Only the .cpp files this
# core actually links against are copied: Common.cpp, Print.cpp,
# Stream.cpp, String.cpp (needs malloc/free/realloc - see
# cores/tangnano20k/tangnano20k_malloc.c), and CanMsg.cpp/
# CanMsgRingbuffer.cpp (for libraries/CAN; only linked when it's used).
# IPAddress.cpp/PluggableUSB.cpp need USB/networking support this
# bare-metal core doesn't provide, so their headers are available (for API
# completeness / future use) but their implementations are left out.
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
for f in Common.cpp Print.cpp Stream.cpp String.cpp CanMsg.cpp CanMsgRingbuffer.cpp; do
  cp "$SRC/$f" "$DST/$f"
done

echo "Vendored ArduinoCore-API headers + {Common,Print,Stream,String,CanMsg,CanMsgRingbuffer}.cpp into $DST"
