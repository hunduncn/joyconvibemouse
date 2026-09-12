#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
developer_dir="/Applications/Xcode.app/Contents/Developer"
app_name="Joy-Con Vibe Remote.app"
legacy_app_name="JoyCon Vibe Remote.app"
bundle_dir="${project_dir}/.build/app/${app_name}"
contents_dir="${bundle_dir}/Contents"

cd "${project_dir}"
DEVELOPER_DIR="${developer_dir}" xcrun swift build -c release --product JoyConVibeRemote
bin_dir="$(DEVELOPER_DIR="${developer_dir}" xcrun swift build -c release --show-bin-path)"

if [[ "${bundle_dir}" != "${project_dir}/.build/app/"* ]]; then
    print -u2 "Refusing to package outside the project build directory."
    exit 1
fi

rm -rf "${bundle_dir}"
mkdir -p "${contents_dir}/MacOS" "${contents_dir}/Resources"
ditto "${bin_dir}/JoyConVibeRemote" "${contents_dir}/MacOS/JoyConVibeRemote"
ditto "${project_dir}/Resources/Info.plist" "${contents_dir}/Info.plist"
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

if [[ "${1:-}" == "--install" ]]; then
    install_dir="/Applications/${app_name}"
    if [[ "${install_dir}" != "/Applications/Joy-Con Vibe Remote.app" ]]; then
        print -u2 "Refusing to replace an unexpected application path."
        exit 1
    fi
    legacy_install_dir="/Applications/${legacy_app_name}"
    if [[ -d "${legacy_install_dir}" ]]; then
        rm -rf "${legacy_install_dir}"
        print "Removed legacy app: ${legacy_install_dir}"
    fi
    rm -rf "${install_dir}"
    ditto "${bundle_dir}" "${install_dir}"
    print "${install_dir}"
else
    print "${bundle_dir}"
fi
