#!/bin/bash
# Selected read-only checks. Do not post full ioreg/nvram output publicly.
set -u
echo 'macOS version:'
sw_vers
echo 'CPU counts:'
sysctl hw.physicalcpu hw.logicalcpu hw.memsize
echo 'Display summary:'
system_profiler SPDisplaysDataType
echo 'AppleSMC service count (expected 1):'
ioreg -r -c AppleSMC -d 0 | grep -c '<class AppleSMC,' || true
echo 'VirtualSMC service count (expected 0 with -vsmccomp):'
ioreg -r -c VirtualSMC -d 0 | grep -c '<class VirtualSMC,' || true
echo 'Loaded graphics/SMC kexts:'
kmutil showloaded 2>/dev/null | grep -E 'nullmoth|VirtualSMC' || true
echo 'en0 built-in property (expected Yes):'
ioreg -r -c IOEthernetInterface -l | grep -E '"BSD Name"|"IOBuiltin"' || true
echo 'VNC listener (use sudo if process ownership is needed):'
lsof -nP -iTCP:5900 -sTCP:LISTEN || true
echo 'Power policy:'
pmset -g custom
echo 'SMBIOS identity verification is intentionally omitted from this shareable summary.'
