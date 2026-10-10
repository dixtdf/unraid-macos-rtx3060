#!/usr/bin/env bash
# Only the idle VFIO-owned RTX 3060 pair; never call libvirt from this script.
set -Eeuo pipefail
[[ $EUID == 0 && $# == 1 ]] || { echo 'Usage (root): resize-bar.sh /path/to/bar.conf' >&2; exit 2; }
for command in realpath stat readlink fuser flock; do command -v "$command" >/dev/null || exit 2; done
config=$(realpath -e -- "$1")
[[ -f $config && $(stat -c %u "$config") == 0 ]] || { echo 'Config must be root-owned' >&2; exit 2; }
mode=$(stat -c %a "$config")
(( (8#$mode & 022) == 0 )) || { echo 'Config is writable by another user/group' >&2; exit 2; }
# shellcheck source=/dev/null
source "$config"
[[ ${GPU_BDF:-} =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.0$ && ${AUDIO_BDF:-} == "${GPU_BDF%.0}.1" ]] || exit 2
[[ ${GPU_DEVICE_ID:-} == 0x2504 && ${AUDIO_DEVICE_ID:-} == 0x228e ]] || exit 2
exec 9>"/var/lock/rtx-bar-${GPU_BDF//[:.]/_}.lock"
flock -n 9 || { echo 'Another BAR operation is running' >&2; exit 2; }
gpu="/sys/bus/pci/devices/$GPU_BDF"; audio="/sys/bus/pci/devices/$AUDIO_BDF"
for dev in "$gpu" "$audio"; do
  [[ -d $dev && $(<"$dev/vendor") == 0x10de && $(basename "$(readlink -f "$dev/driver")") == vfio-pci ]] || { echo 'Device is missing or not VFIO-owned' >&2; exit 2; }
done
[[ $(<"$gpu/device") == "$GPU_DEVICE_ID" && $(<"$audio/device") == "$AUDIO_DEVICE_ID" ]] || exit 2
# Require both group and optional modern VFIO cdev nodes to be unoccupied.
for dev in "$gpu" "$audio"; do
  group=$(basename "$(readlink -f "$dev/iommu_group")")
  [[ $group =~ ^[0-9]+$ && -e /dev/vfio/$group ]] || exit 2
  if fuser "/dev/vfio/$group" >/dev/null 2>&1; then echo 'VFIO group is in use; stop its VM/container normally' >&2; exit 2; fi
  shopt -s nullglob
  for node in "$dev"/vfio-dev/vfio*; do
    cdev="/dev/vfio/devices/$(basename "$node")"
    if [[ -e $cdev ]] && fuser "$cdev" >/dev/null 2>&1; then echo 'VFIO cdev is in use' >&2; exit 2; fi
  done
done
bar_size() {
  local start end flags
  read -r start end flags < <(sed -n '2p' "$gpu/resource")
  [[ $start =~ ^0x[0-9a-fA-F]+$ && $end =~ ^0x[0-9a-fA-F]+$ ]] || return 1
  printf '%s\n' "$(( end - start + 1 ))"
}
[[ -r $gpu/resource1_resize && -w $gpu/resource1_resize ]] || { echo 'No writable BAR1 resize interface' >&2; exit 2; }
supported=$(<"$gpu/resource1_resize")
[[ $supported =~ ^[0-9a-fA-F]+$ ]] && (( (16#$supported & (1 << 13)) != 0 )) || { echo '8GiB BAR1 is not advertised' >&2; exit 2; }
if [[ $(bar_size) == 8589934592 ]]; then echo 'BAR1 is already 8GiB'; exit 0; fi
unbound_gpu=0; unbound_audio=0
rebind() {
  local status=$? failed=0
  trap - EXIT
  if (( unbound_gpu )); then printf '%s' "$GPU_BDF" > /sys/bus/pci/drivers/vfio-pci/bind || failed=1; fi
  if (( unbound_audio )); then printf '%s' "$AUDIO_BDF" > /sys/bus/pci/drivers/vfio-pci/bind || failed=1; fi
  (( ! failed )) || { echo 'VFIO rebind failed; inspect both devices before starting VM' >&2; status=1; }
  exit "$status"
}
trap rebind EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s' "$AUDIO_BDF" > /sys/bus/pci/drivers/vfio-pci/unbind; unbound_audio=1
printf '%s' "$GPU_BDF" > /sys/bus/pci/drivers/vfio-pci/unbind; unbound_gpu=1
printf '%s' 13 > "$gpu/resource1_resize"
[[ $(bar_size) == 8589934592 ]] || { echo 'BAR1 did not become 8GiB; inspect MMIO space' >&2; exit 2; }
echo 'BAR1 set to 8GiB; rebinding the two VFIO functions.'
