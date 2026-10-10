#!/usr/bin/env bash
# Cold backup of the two template disks, NVRAM and XML. No stop/start/destroy.
set -Eeuo pipefail
umask 077
[[ $# == 2 && $EUID == 0 ]] || { echo 'Usage (root): checkpoint.sh VM_NAME VM_ROOT' >&2; exit 2; }
vm=$1; root=$(realpath -e -- "$2")
[[ $vm =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ && $root != / && $root != /mnt && $root != /mnt/user && $root != /mnt/user/domains ]] || exit 2
for command in virsh qemu-img realpath sha256sum mktemp flock; do command -v "$command" >/dev/null || exit 2; done
exec 9>"/var/lock/macos-checkpoint-$vm.lock"; flock -n 9 || exit 2
[[ $(LC_ALL=C virsh domstate "$vm") == 'shut off' ]] || { echo 'VM must be shut off; this script never forces it off' >&2; exit 2; }
for rel in vdisk1.qcow2 efi/OpenCore.raw nvram/VARS.fd; do
  path=$(realpath -e -- "$root/$rel")
  [[ $path == "$root/"* && -f $path && ! -L "$root/$rel" ]] || { echo 'Disk/NVRAM path escapes VM root or is missing' >&2; exit 2; }
done
# Prevent a manual backup from accidentally capturing paths different from the live definition.
xml=$(LC_ALL=C virsh dumpxml --inactive "$vm")
for rel in vdisk1.qcow2 efi/OpenCore.raw nvram/VARS.fd; do
  [[ $xml == *"$root/$rel"* ]] || { echo 'VM XML paths differ from the template; review and adapt backup paths' >&2; exit 2; }
done
qemu-img check -f qcow2 "$root/vdisk1.qcow2"
mkdir -p "$root/checkpoints"
base=$(realpath -e -- "$root/checkpoints"); [[ $base == "$root/checkpoints" ]] || exit 2
backup=$(mktemp -d "$base/cold-$(date +%Y%m%d-%H%M%S).XXXXXX")
printf '%s\n' "$xml" > "$backup/domain.xml"
mkdir "$backup/efi" "$backup/nvram"
for rel in vdisk1.qcow2 efi/OpenCore.raw nvram/VARS.fd; do
  cp --reflink=auto --sparse=always -- "$root/$rel" "$backup/$rel"
done
[[ $(LC_ALL=C virsh domstate "$vm") == 'shut off' ]] || { echo 'VM started during backup; checkpoint is invalid' >&2; exit 2; }
qemu-img check -f qcow2 "$backup/vdisk1.qcow2"
(cd "$backup"; sha256sum vdisk1.qcow2 efi/OpenCore.raw nvram/VARS.fd domain.xml > SHA256SUMS)
sync
echo "Cold checkpoint complete: $backup (private XML/identity; never publish)."
