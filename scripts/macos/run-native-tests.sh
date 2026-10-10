#!/usr/bin/env bash
# Requires existing Apple Command Line Tools; outputs stay in local/.
set -Eeuo pipefail
[[ $(uname -s) == Darwin && $(uname -m) == x86_64 ]] || { echo 'Run on the Intel macOS guest' >&2; exit 2; }
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
out="$repo/local/native-tests"
mkdir -p "$out"
xcrun --find clang >/dev/null
xcrun clang -O2 -fobjc-arc -framework Foundation -framework Metal \
  "$repo/tests/native/metal-acceptance.m" -o "$out/metal-acceptance"
xcrun clang -O2 -fobjc-arc -framework Foundation -framework VideoToolbox \
  -framework CoreVideo -framework CoreMedia \
  "$repo/tests/native/video-acceptance.m" -o "$out/video-acceptance"
# A Metal failure does not prevent collecting video evidence.
set +e
"$out/metal-acceptance" > "$out/metal.json" 2> "$out/metal.stderr.log"
metal_status=$?
"$out/video-acceptance" > "$out/video.json" 2> "$out/video.stderr.log"
video_status=$?
set -e
echo "Metal exit: $metal_status; video process exit: $video_status"
echo "Reports: $out"
echo 'The video process exit code only means a report was produced; inspect pixel MAE and HW flags for each codec.'
[[ $metal_status == 0 && $video_status == 0 ]]
