#!/usr/bin/env bash
#
# Build / simulate / package helper for Circles Ultra.
#
# Requires the Garmin Connect IQ SDK (it could not be downloaded in the
# environment where this project was authored, so nothing here assumes it is
# already on PATH - point CIQ_SDK at your install or run the SDK's bin dir).
#
#   export CIQ_SDK=~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-*/
#   ./build.sh sim fr165          # build for FR165 and open the simulator
#   ./build.sh build fr165        # build a debug .prg
#   ./build.sh package            # build the store .iq for every product
#
# A developer key is needed to build. Generate one once with:
#   openssl genrsa -out developer_key.pem 4096
#   openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt \
#           -in developer_key.pem -out developer_key
#
set -euo pipefail
cd "$(dirname "$0")"

KEY="${CIQ_KEY:-developer_key}"
BIN="bin"
DEVICE="${2:-fr165}"

sdk_bin() {
    if [[ -n "${CIQ_SDK:-}" ]]; then echo "${CIQ_SDK%/}/bin/$1"; else echo "$1"; fi
}
MONKEYC="$(sdk_bin monkeyc)"
MONKEYDO="$(sdk_bin monkeydo)"

if [[ ! -f "$KEY" ]]; then
    echo "No developer key at '$KEY'. See the header of this script to create one." >&2
    exit 1
fi
mkdir -p "$BIN"

case "${1:-build}" in
    build)
        "$MONKEYC" -f monkey.jungle -o "$BIN/CirclesUltra-$DEVICE.prg" \
                   -y "$KEY" -d "$DEVICE" -w
        echo "built $BIN/CirclesUltra-$DEVICE.prg"
        ;;
    sim)
        "$MONKEYC" -f monkey.jungle -o "$BIN/CirclesUltra-$DEVICE.prg" \
                   -y "$KEY" -d "$DEVICE" -w
        # connectiq launches the simulator; monkeydo loads the prg into it.
        ( connectiq >/dev/null 2>&1 & ) || true
        sleep 2
        "$MONKEYDO" "$BIN/CirclesUltra-$DEVICE.prg" "$DEVICE"
        ;;
    package)
        # The store-ready .iq bundle covering every product in the manifest.
        "$MONKEYC" -f monkey.jungle -o "$BIN/CirclesUltra.iq" -y "$KEY" -e -w
        echo "packaged $BIN/CirclesUltra.iq  (upload this to the Connect IQ Store)"
        ;;
    *)
        echo "usage: $0 {build|sim|package} [device]" >&2
        exit 2
        ;;
esac
