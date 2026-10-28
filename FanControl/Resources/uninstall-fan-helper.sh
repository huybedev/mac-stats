#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || exit 1
identifier=com.openhoangnc.macstats.FanHelper
helper="/Library/PrivilegedHelperTools/$identifier"
support='/Library/Application Support/MacStats/FanControl'
if /bin/launchctl print "system/$identifier" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/$identifier"
fi
for i in {1..30}; do
    /usr/bin/pgrep -f "^$helper$" >/dev/null || break
    /bin/sleep 0.2
done
/usr/bin/pgrep -f "^$helper$" >/dev/null && { echo 'Bộ trợ giúp chưa dừng.' >&2; exit 1; }
if [[ -e "$support/recovery.json" ]]; then
    /bin/launchctl bootstrap system "/Library/LaunchDaemons/$identifier.plist"
    echo 'Chưa xác nhận quạt trở về macOS. Đã giữ bộ trợ giúp để thử phục hồi; hãy mở MacStats và thử lại.' >&2
    exit 1
fi
/bin/rm -f "/Library/LaunchDaemons/$identifier.plist" "$helper" "$support/client-requirement"
/bin/rmdir "$support" 2>/dev/null || true
echo 'Đã gỡ bộ trợ giúp; quạt do macOS quản lý.'
