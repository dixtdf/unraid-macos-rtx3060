#!/usr/bin/env bash
# Build a new EFI disk; never attach it to a running VM.
set -Eeuo pipefail
umask 077
[[ $# == 4 && $EUID == 0 ]] || { echo 'Usage (root): build-efi-image.sh ISO CONFIG OCVALIDATE NEW.raw' >&2; exit 2; }
for command in sha256sum sgdisk mkfs.vfat losetup mount umount realpath truncate mktemp; do
  command -v "$command" >/dev/null || { echo "Missing $command" >&2; exit 2; }
done
iso=$(realpath -e -- "$1"); config=$(realpath -e -- "$2"); validator=$(realpath -e -- "$3")
[[ -f $iso && -f $config && -x $validator && $4 == *.raw && ! -e $4 && ! -L $4 ]] || { echo 'Invalid input or output already exists' >&2; exit 2; }
parent=$(realpath -e -- "$(dirname -- "$4")"); output="$parent/$(basename -- "$4")"
[[ ! -e $output && ! -L $output && $parent != /dev && $parent != /proc && $parent != /sys ]] || exit 2
printf '%s  %s\n' '287328995d4198f1b05166f087d85bf7ef66bedafe150d17ad112ac8de60051d' "$iso" | sha256sum -c - >/dev/null
validation=$("$validator" "$config")
printf '%s\n' "$validation"
[[ $validation == *1.0.5* ]] || { echo 'Use ocvalidate matching OpenCore 1.0.5' >&2; exit 2; }
work=$(mktemp -d "$parent/.efi-build.XXXXXX"); mkdir "$work/iso" "$work/esp"
loop=''; iso_mounted=0; esp_mounted=0
cleanup() {
  local status=$? failed=0
  trap - EXIT
  if (( esp_mounted )); then umount -- "$work/esp" || failed=1; fi
  if [[ -n $loop ]] && (( ! failed )); then losetup -d -- "$loop" || failed=1; fi
  if (( iso_mounted )); then umount -- "$work/iso" || failed=1; fi
  if (( failed )); then echo "Cleanup incomplete: inspect $work and $loop" >&2; status=1
  else rmdir "$work/esp" "$work/iso" "$work" || true; fi
  (( status == 0 )) || echo 'Failed build: retain and inspect the partial output; do not boot it.' >&2
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mount -t iso9660 -o loop,ro,nosuid,nodev,noexec -- "$iso" "$work/iso"; iso_mounted=1
source_efi="$work/iso/efi_release/efi"
printf '%s  %s\n' 'a78f699080543456c29551134b78f1bb59f69ec38bc94b59b3c04bb5f28bdd12' "$source_efi/oc/opencore.efi" | sha256sum -c - >/dev/null
printf '%s  %s\n' 'a7493c410bd88f90736c0b0137d1af63694fc18168a65b2d1351ff64c40b0d65' "$source_efi/oc/drivers/openruntime.efi" | sha256sum -c - >/dev/null
# noclobber reserves a new regular file before any partition operation.
(set -o noclobber; : > "$output")
truncate -s 512M -- "$output"
sgdisk --clear --new=1:2048:0 --typecode=1:ef00 --change-name=1:OpenCore -- "$output" >/dev/null
loop=$(losetup --find --show --partscan -- "$output")
[[ $loop =~ ^/dev/loop[0-9]+$ ]] || exit 2
for (( i=0; i<50; i++ )); do [[ -b ${loop}p1 ]] && break; sleep 0.1; done
[[ -b ${loop}p1 ]] || exit 2
mkfs.vfat -F 32 -n OCINSTALL -- "${loop}p1" >/dev/null
mount -t vfat -o rw,nosuid,nodev,noexec,umask=0077 -- "${loop}p1" "$work/esp"; esp_mounted=1
cp -r -- "$source_efi" "$work/esp/EFI"
cp -- "$config" "$work/esp/EFI/OC/config.plist"
cmp -- "$config" "$work/esp/EFI/OC/config.plist"
sync
echo "Built new EFI image: $output (contains private identity; keep it local)."
