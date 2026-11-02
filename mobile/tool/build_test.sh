#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

bash tool/build_release.sh --android-project-arg=ourSpaceTestApp=true "$@"

out_dir="build/app/outputs/flutter-apk"
test_dir="build/test-app"
mkdir -p "$test_dir"
mv "$out_dir/app-arm64-v8a-release.apk" "$test_dir/our-space-test.apk"
rm -f "$out_dir/app-arm64-v8a-release.apk.sha1"

echo "Test app: $PWD/$test_dir/our-space-test.apk"
