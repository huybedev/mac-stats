#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Cần quyền quản trị.' >&2; exit 1; }
app=${1:?Missing app path}
identifier=com.openhoangnc.macstats.FanHelper
support='/Library/Application Support/MacStats/FanControl'
helper="/Library/PrivilegedHelperTools/$identifier"
plist="/Library/LaunchDaemons/$identifier.plist"
/usr/bin/codesign --verify --strict "$app"
/usr/bin/codesign --verify --strict "$app/Contents/Resources/MacStatsFanHelper"
hash=$(/usr/bin/codesign -dv --arch arm64 --verbose=4 "$app/Contents/MacOS/MacStats" 2>&1 | /usr/bin/awk -F= '/^CDHash=/{print $2}')
intel_hash=$(/usr/bin/codesign -dv --arch x86_64 --verbose=4 "$app/Contents/MacOS/MacStats" 2>&1 | /usr/bin/awk -F= '/^CDHash=/{print $2}')
[[ "$intel_hash" =~ ^[0-9a-f]{40}$ ]] || exit 1
[[ "$hash" =~ ^[0-9a-f]{40}$ ]] || { echo 'Không xác minh được chữ ký MacStats.' >&2; exit 1; }
requirement="identifier \"com.openhoangnc.macstats\" and (cdhash H\"$hash\" or cdhash H\"$intel_hash\")"
/usr/bin/codesign --verify --all-architectures --strict -R "=$requirement" "$app"
[[ ! -L "/Library/Application Support/MacStats" && ! -L "$support" && ! -L "$helper" && ! -L "$plist" ]] || { echo 'Đường dẫn cài đặt không hợp lệ.' >&2; exit 1; }
if /bin/launchctl print "system/$identifier" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/$identifier"
fi
# Allow the old helper to finish its synchronous SMC cleanup before replacement.
for i in {1..30}; do
    /usr/bin/pgrep -f "^$helper$" >/dev/null || break
    /bin/sleep 0.2
done
/usr/bin/pgrep -f "^$helper$" >/dev/null && { echo 'Bộ trợ giúp cũ chưa dừng. Hãy thử lại.' >&2; exit 1; }
/usr/bin/install -d -o root -g wheel -m 755 "$support" /Library/PrivilegedHelperTools
[[ ! -L "$support/client-requirement" && ! -L "$support/recovery.json" ]] || exit 1
/usr/bin/install -o root -g wheel -m 755 "$app/Contents/Resources/MacStatsFanHelper" "$helper"
/usr/bin/printf '%s\n' "$requirement" > "$support/client-requirement"
/usr/sbin/chown root:wheel "$support/client-requirement"
/bin/chmod 644 "$support/client-requirement"
/usr/bin/install -o root -g wheel -m 644 "$app/Contents/Resources/$identifier.plist" "$plist"
/bin/launchctl bootstrap system "$plist"
/bin/launchctl kickstart "system/$identifier"
echo 'Đã cài bộ trợ giúp MacStats.'
