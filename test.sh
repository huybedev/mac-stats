#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
build=$(mktemp -d "${TMPDIR:-/tmp}/macstats-tests.XXXXXX")
trap 'rm -rf "$build"' EXIT
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$build/modules" \
    FanControl/Models.swift FanControl/Activity.swift FanControl/FanSMC.swift FanControl/Platform.swift \
    FanControl/Controller.swift FanControl/Localization.swift Tests/FanControlTests.swift \
    -o "$build/tests" -framework IOKit
"$build/tests"
for script in build.sh install.sh uninstall.sh FanControl/Resources/*.sh; do
    /bin/bash -n "$script"
done
/usr/bin/plutil -lint Info.plist FanControl/Resources/*.plist
