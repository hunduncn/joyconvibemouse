#!/bin/zsh
set -euo pipefail

# Called only after a successful build. Also supports a user-owned Applications
# directory so installing does not require sudo or change preference ownership.
if (( $# != 3 )); then
    print -u2 'Usage: install-app.sh BUNDLE INSTALL_DIRECTORY QUIT_HELPER'
    exit 1
fi
source_bundle="${1:A}"
install_root="${2:A}"
quit_helper="${3:A}"
app_name='Joy-Con Vibe Remote.app'
bundle_id='com.aqxp.JoyConVibeRemote'

validate_bundle() {
    local candidate="$1"
    [[ -d "$candidate" && ! -L "$candidate" ]] &&
        [[ "$(plutil -extract CFBundleIdentifier raw -o - "$candidate/Contents/Info.plist")" == "$bundle_id" ]]
}

validate_bundle "$source_bundle" || { print -u2 'Source app has an unexpected identity.'; exit 1; }
[[ -x "$quit_helper" ]] || { print -u2 'Missing app termination helper.'; exit 1; }
mkdir -p "$install_root"
[[ -w "$install_root" ]] || {
    print -u2 'Installation directory is not writable. Use --install-dir "$HOME/Applications".'
    exit 1
}
target="$install_root/$app_name"
legacy="$install_root/JoyCon Vibe Remote.app"
[[ "$source_bundle" != "$target" && "$source_bundle" != "$legacy" ]] || exit 1
for candidate in "$target" "$legacy"; do
    if [[ -e "$candidate" || -L "$candidate" ]]; then
        validate_bundle "$candidate" || {
            print -u2 "Refusing to replace an unrelated app or symlink: $candidate"
            exit 1
        }
    fi
done

transaction="$(mktemp -d "$install_root/.joycon-vibe-remote-install.XXXXXX")"
staged="$transaction/$app_name"
current_backup="$transaction/previous-current"
legacy_backup="$transaction/previous-legacy"
committed=false
new_installed=false

finish_install() {
    local result=$?
    trap - EXIT INT TERM HUP
    if ! $committed; then
        # All moves stay on one volume. If replacement fails, put the old
        # bundle back; retain the transaction if even rollback cannot finish.
        local rollback_ok=true
        if $new_installed; then
            mv "$target" "$transaction/failed-new" || rollback_ok=false
        fi
        if [[ -d "$current_backup" ]]; then
            mv "$current_backup" "$target" || rollback_ok=false
        fi
        if [[ -d "$legacy_backup" ]]; then
            mv "$legacy_backup" "$legacy" || rollback_ok=false
        fi
        if ! $rollback_ok; then
            print -u2 "Rollback needs attention; original bundles are preserved in $transaction"
            exit 1
        fi
    fi
    if [[ -d "$current_backup" || -d "$legacy_backup" ]]; then
        print "Previous app backup retained: $transaction"
    else
        # This exact directory was created by mktemp above and contains only
        # this installation's disposable staging files.
        rm -rf -- "$transaction"
    fi
    exit "$result"
}
trap finish_install EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

ditto "$source_bundle" "$staged"
codesign --verify --deep --strict "$staged"
"$quit_helper" "$target" "$legacy"

if [[ -d "$target" ]]; then mv "$target" "$current_backup"; fi
if [[ -d "$legacy" ]]; then mv "$legacy" "$legacy_backup"; fi
mv "$staged" "$target"
new_installed=true
codesign --verify --deep --strict "$target"
committed=true
print "$target"
