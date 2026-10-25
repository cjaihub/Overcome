#!/usr/bin/env bash
# Installs Ovacome on an Android phone over Wi-Fi (or USB).
#
# One-time, on the phone (Android 11+):
#   Settings → About phone → tap "Build number" 7× (enables Developer options)
#   Settings → Developer options → Wireless debugging → ON
#
# Usage:
#   ./scripts/install-android.sh pair 192.168.1.20:37099 123456   # "Pair device with pairing code" screen
#   ./scripts/install-android.sh connect 192.168.1.20:41231       # IP:port shown on the Wireless debugging screen
#   ./scripts/install-android.sh install ~/Downloads/ovacome-apks  # folder or .apk from the GitHub Actions artifact
#   ./scripts/install-android.sh run                               # build from source and install (needs Flutter)
set -euo pipefail

command -v adb >/dev/null || { echo "adb not found. Install Android platform-tools: https://developer.android.com/tools/releases/platform-tools"; exit 1; }

case "${1:-}" in
  pair)    adb pair "$2" "$3" ;;
  connect) adb connect "$2" && adb devices ;;
  install)
    src="${2:?path to an .apk or the unzipped ovacome-apks folder}"
    if [[ -d "$src" ]]; then
      abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
      apk="$src/ovacome-$abi.apk"
      [[ -f "$apk" ]] || apk="$src/ovacome-universal.apk"
    else
      apk="$src"
    fi
    echo "Installing $(basename "$apk")…"
    adb install -r "$apk"
    adb shell monkey -p com.overcome.overcome -c android.intent.category.LAUNCHER 1 >/dev/null
    echo "Installed and launched." ;;
  run)     flutter run --release ;;
  *)       sed -n '2,15p' "$0" ;;
esac
