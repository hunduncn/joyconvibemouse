#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_name="Joy-Con Vibe Remote.app"
bundle_dir="${project_dir}/.build/app/${app_name}"
contents_dir="${bundle_dir}/Contents"
install_root="/Applications"
install_requested=false

if [[ "${1:-}" == "--install" ]]; then
    install_requested=true
    shift
    if [[ "${1:-}" == "--install-dir" && $# == 2 ]]; then
        install_root="$2"
        shift 2
    fi
fi
if (( $# != 0 )); then
    print -u2 'Usage: ./scripts/build-app.sh [--install [--install-dir DIRECTORY]]'
    exit 1
fi

if [[ "$(uname -s)" != Darwin ]]; then
    print -u2 'This app requires macOS 14 or newer.'
    exit 1
fi
os_version="$(sw_vers -productVersion)"
if (( ${os_version%%.*} < 14 )); then
    print -u2 'This app requires macOS 14 or newer.'
    exit 1
fi
# Honor the caller's selection. When only CLT is selected, discover a full
# Xcode instead of assuming it lives at a fixed path. New SwiftUI SDKs require
# compiler plugins that are not shipped in standalone Command Line Tools.
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    developer_dir="$DEVELOPER_DIR"
    [[ "$developer_dir" == *.app ]] && developer_dir="$developer_dir/Contents/Developer"
else
    developer_dir="$(xcode-select -p 2>/dev/null || true)"
    if [[ ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
        while IFS= read -r candidate; do
            if [[ -x "$candidate/Contents/Developer/usr/bin/xcodebuild" ]]; then
                developer_dir="$candidate/Contents/Developer"
                break
            fi
        done < <(mdfind 'kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"')
    fi
fi
if [[ ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
    print -u2 'Full Xcode 16+ is required; standalone Command Line Tools are insufficient.'
    print -u2 'Install and open Xcode once, then set DEVELOPER_DIR to its Contents/Developer directory.'
    exit 1
fi
export DEVELOPER_DIR="$developer_dir"
print "Using developer tools: $DEVELOPER_DIR"
if ! swift_version="$(xcrun swift --version 2>&1)"; then
    print -u2 "${swift_version}"
    print -u2 'Install and open Xcode 16+ (Swift 6+), then check xcode-select -p.'
    exit 1
fi
swift_major="$(print -r -- "$swift_version" | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -n 1)"
if [[ -z "$swift_major" ]] || (( swift_major < 6 )); then
    print -u2 "Swift 6+ is required. Selected toolchain: ${swift_version}"
    exit 1
fi
xcrun --sdk macosx --show-sdk-path >/dev/null

cd "${project_dir}"
xcrun swift build -c release --product JoyConVibeRemote
bin_dir="$(xcrun swift build -c release --show-bin-path)"

if [[ "${bundle_dir}" != "${project_dir}/.build/app/"* ]]; then
    print -u2 "Refusing to package outside the project build directory."
    exit 1
fi

rm -rf "${bundle_dir}"
mkdir -p "${contents_dir}/MacOS" "${contents_dir}/Resources"
ditto "${bin_dir}/JoyConVibeRemote" "${contents_dir}/MacOS/JoyConVibeRemote"
ditto "${project_dir}/Resources/Info.plist" "${contents_dir}/Info.plist"
ditto "${project_dir}/THIRD_PARTY_NOTICES.md" "${contents_dir}/Resources/THIRD_PARTY_NOTICES.md"
chmod 755 "${contents_dir}/MacOS/JoyConVibeRemote"
# Keep a stable designated requirement across local ad-hoc rebuilds. Without
# this, macOS derives the requirement from the binary CDHash and Accessibility
# permission is invalidated after every code change.
codesign \
    --force \
    --deep \
    --sign - \
    --requirements '=designated => identifier "com.aqxp.JoyConVibeRemote"' \
    "${bundle_dir}"
codesign --verify --deep --strict "${bundle_dir}"

if $install_requested; then
    quit_helper="${project_dir}/.build/quit-installed-joycon"
    xcrun swiftc "${script_dir}/quit-installed-app.swift" -o "$quit_helper"
    /bin/zsh "${script_dir}/install-app.sh" "$bundle_dir" "$install_root" "$quit_helper"
else
    print "${bundle_dir}"
fi
