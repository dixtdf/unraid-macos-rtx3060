#!/usr/bin/env bash
# Copy as an executable libvirt qemu.d hook after reading docs/04.
set -Eeuo pipefail
config=/etc/macos-rtx-bar.conf
[[ ${2:-} == prepare && ${3:-} == begin ]] || exit 0
[[ -e $config ]] || exit 0
[[ $(stat -c %u "$config") == 0 ]] || exit 2
mode=$(stat -c %a "$config")
(( (8#$mode & 022) == 0 )) || exit 2
# shellcheck source=/dev/null
source "$config"
[[ ${1:-} == "${VM_NAME:-}" ]] || exit 0
# No virsh/libvirt calls here: a hook is invoked within libvirt's VM operation.
exec /usr/local/sbin/macos-rtx-resize-bar "$config"
