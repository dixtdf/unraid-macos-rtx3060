#!/usr/bin/env bash
# New exFAT delivery disk. Requires mkfs.exfat; no VM changes.
set -Eeuo pipefail
umask 077
[[ $# == 3 && $EUID == 0 ]] || { echo 'Usage (root): build-delivery-image.sh PACKAGE PAYLOAD.cpio NEW.raw' >&2; exit 2; }
for command in realpath mktemp losetup sgdisk mkfs.exfat mount umount truncate; do
  command -v "$command" >/dev/null || { echo "Missing $command" >&2; exit 2; }
done
pkg=$(realpath -e -- "$1"); payload=$(realpath -e -- "$2")
[[ -f $pkg && -f $payload && $3 == *.raw && ! -e $3 && ! -L $3 ]] || exit 2
parent=$(realpath -e -- "$(dirname -- "$3")"); output="$parent/$(basename -- "$3")"
[[ ! -e $output && ! -L $output && $parent != /dev && $parent != /sys && $parent != /proc ]] || exit 2
work=$(mktemp -d "$parent/.delivery-build.XXXXXX"); loop=''; mounted=0
cleanup() {
  local status=$? failed=0
  trap - EXIT
  if (( mounted )); then umount -- "$work" || failed=1; fi
  if [[ -n $loop ]] && (( ! failed )); then losetup -d -- "$loop" || failed=1; fi
  if (( failed )); then echo "Cleanup incomplete: inspect $work and $loop" >&2; status=1
  else rmdir "$work" || true; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
(set -o noclobber; : > "$output")
truncate -s 32G -- "$output"
sgdisk --clear --new=1:2048:0 --typecode=1:0700 -- "$output" >/dev/null
loop=$(losetup --find --show --partscan -- "$output")
[[ $loop =~ ^/dev/loop[0-9]+$ ]] || exit 2
for (( i=0; i<50; i++ )); do [[ -b ${loop}p1 ]] && break; sleep 0.1; done
[[ -b ${loop}p1 ]] || exit 2
mkfs.exfat -L Delivery "${loop}p1" >/dev/null
mount -t exfat -o rw,nosuid,nodev,noexec -- "${loop}p1" "$work"; mounted=1
cp -- "$pkg" "$work/InstallAssistant-15.8.1-24H32.pkg"
cp -- "$payload" "$work/Payload.cpio"
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
cp -- "$script_dir/../macos/build-installer.sh" "$work/build-installer.sh"
cmp -- "$pkg" "$work/InstallAssistant-15.8.1-24H32.pkg"
cmp -- "$payload" "$work/Payload.cpio"
sync
echo "Built new Delivery image: $output"
