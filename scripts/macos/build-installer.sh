#!/bin/sh
# Recovery-only helper for the pinned XAR/DMG hybrid InstallAssistant package.
set -eu
stage=${1:?Usage: build-installer.sh DELIVERY_VOLUME INSTALLER_VOLUME}
target=${2:?Dedicated empty Installer volume required}
[ "$(id -u)" = 0 ] || { echo 'Run in Recovery as root' >&2; exit 2; }
[ -d "$stage" ] && [ -d "$target" ] && [ "$target" = /Volumes/Installer ] || { echo 'Target must be the dedicated /Volumes/Installer volume' >&2; exit 2; }
[ "$stage" != "$target" ] || exit 2
pkg="$stage/InstallAssistant-15.8.1-24H32.pkg"
[ -f "$pkg" ] && [ -f "$stage/Payload.cpio" ] || exit 2
expected=e4532e3337431292a7f227fcde7eb57f7b907547e2a26b43d3aab5a3f6e44781
actual=$(/usr/bin/shasum -a 256 "$pkg" | /usr/bin/awk '{print $1}')
[ "$actual" = "$expected" ] || { echo 'Package SHA256 mismatch' >&2; exit 2; }
/usr/sbin/diskutil info "$target"
printf 'createinstallmedia will ERASE the Installer volume. Type ERASE-Installer: '
IFS= read -r answer
[ "$answer" = ERASE-Installer ] || exit 2
work=$(/usr/bin/mktemp -d /tmp/macos-installer.XXXXXX)
cd "$work"
/usr/bin/cpio -idm < "$stage/Payload.cpio"
app=$(/usr/bin/find "$work" -type d -name 'Install macOS Sequoia.app' -prune | /usr/bin/head -n 1)
[ -n "$app" ] && [ -f "$app/Contents/Resources/createinstallmedia" ] || exit 2
mkdir -p "$app/Contents/SharedSupport"
ln -s "$pkg" "$app/Contents/SharedSupport/SharedSupport.dmg"
chmod 0755 "$app/Contents/Resources/createinstallmedia"
"$app/Contents/Resources/createinstallmedia" --volume "$target" --nointeraction
