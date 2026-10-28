import Foundation

enum FanLanguage: String, CaseIterable, Identifiable {
    case vietnamese = "vi", english = "en", chinese = "zh-Hans"
    var id: String { rawValue }
    var name: String {
        switch self { case .vietnamese: return "Tiếng Việt"; case .english: return "English"; case .chinese: return "简体中文" }
    }

    func text(_ key: String) -> String {
        guard self != .vietnamese, let pair = Self.translations[key] else { return key }
        return self == .english ? pair.0 : pair.1
    }
    func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), arguments: args)
    }

    // Helper errors are deliberately sent as plain text for backwards
    // compatibility. Translate their known phrases at the presentation layer,
    // including nested errors and dynamic SMC key/error details.
    func message(_ value: String) -> String {
        guard self != .vietnamese else { return value }
        var result = value
        for key in Self.translations.keys.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: key, with: text(key))
        }
        let patterns: [(String, String, String)] = [
            (#"Không đọc được trạng thái quạt (\d+)\."#, "Could not read fan $1 status.", "无法读取风扇 $1 的状态。"),
            (#"Quạt (\d+) chưa trở về macOS\."#, "Fan $1 has not returned to macOS control.", "风扇 $1 尚未交还 macOS 控制。"),
            (#"Không hỗ trợ ghi kiểu SMC (.+?)\."#, "Cannot write SMC type $1.", "不支持写入 SMC 类型 $1。"),
            (#"Không mở được SMC: (.+?)\."#, "Could not open SMC: $1.", "无法打开 SMC：$1。"),
            (#"SMC (\w{4}) từ chối lệnh \((.+?)\)\."#, "SMC $1 rejected the command ($2).", "SMC $1 拒绝了命令（$2）。"),
            (#"SMC (\w{4}) không có dữ liệu\."#, "SMC $1 has no data.", "SMC $1 没有数据。")
        ]
        for (pattern, english, chinese) in patterns {
            result = result.replacingOccurrences(of: pattern, with: self == .english ? english : chinese, options: .regularExpression)
        }
        return result
    }
    private static let translations: [String: (String, String)] = [
        "Ngôn ngữ": ("Language", "语言"),
        "Mở MacStats": ("Open MacStats", "打开 MacStats"),
        "Bật theo nhiệt độ CPU": ("Use CPU temperature", "按 CPU 温度调节"),
        "Trả quyền cho macOS": ("Return control to macOS", "交还 macOS 控制"),
        "Thoát MacStats": ("Quit MacStats", "退出 MacStats"),
        "Chỉ theo dõi": ("Monitoring only", "仅监控"),
        "Quạt %d: %d RPM": ("Fan %d: %d RPM", "风扇 %d：%d RPM"),
        "NHIỆT ĐỘ CPU": ("CPU TEMPERATURE", "CPU 温度"),
        "TỐC ĐỘ QUẠT": ("FAN SPEED", "风扇转速"),
        "NHIỆT ĐỘ GPU": ("GPU TEMPERATURE", "GPU 温度"),
        "CPU/GPU từ 90°C: yêu cầu quạt tối đa. Khi thoát, mất kết nối hoặc mất cảm biến: trả quyền cho macOS. Đóng cửa sổ vẫn chạy ở thanh menu.": ("At 90°C CPU/GPU, maximum fan speed is requested. On quit, disconnect, or sensor failure, control returns to macOS. Closing the window keeps the app in the menu bar.", "CPU/GPU 达到 90°C 时请求最高转速。退出、连接中断或传感器故障时，控制权交还 macOS。关闭窗口后应用仍在菜单栏运行。"),
        "Gỡ bộ trợ giúp MacStats?": ("Remove the MacStats helper?", "移除 MacStats 辅助程序？"),
        "Hủy": ("Cancel", "取消"), "Gỡ": ("Remove", "移除"),
        "Quạt được trả về macOS. Bạn vẫn có thể theo dõi nhiệt độ và cài lại bộ trợ giúp sau.": ("Control returns to macOS. You can still monitor temperatures and reinstall the helper later.", "控制权将交还 macOS。您仍可监控温度，并可稍后重新安装辅助程序。"),
        "MÁT HƠN. CHỦ ĐỘNG HƠN.": ("COOLER. IN CONTROL.", "冷静运行，自主管控。"),
        "Điều khiển quạt": ("Fan control", "风扇控制"),
        "KHỞI ĐỘNG": ("STARTUP", "启动"),
        "Mở khi đăng nhập": ("Open at login", "登录时打开"),
        "Tự bật đường nhiệt khi mở": ("Enable CPU curve on launch", "启动时启用温度曲线"),
        "Chỉ bật khi bạn đã chọn và áp dụng đường nhiệt phù hợp.": ("Use a suitable curve and apply it first.", "请先选择并应用合适的温度曲线。"),
        "Bộ trợ giúp đã kết nối": ("Helper connected", "辅助程序已连接"),
        "Chế độ theo dõi": ("Monitoring mode", "监控模式"),
        "Cập nhật bộ trợ giúp": ("Update helper", "更新辅助程序"),
        "Cài bộ trợ giúp": ("Install helper", "安装辅助程序"),
        "Gỡ bộ trợ giúp…": ("Remove helper…", "移除辅助程序…"),
        "Yêu cầu quyền quản trị để điều khiển quạt.": ("Administrator access is required for fan control.", "控制风扇需要管理员权限。"),
        "MacStats · Chạy hoàn toàn trên máy": ("MacStats · Runs locally", "MacStats · 本机运行"),
        "Kiểm soát luồng gió.": ("Take control of cooling.", "掌控散热。"),
        "Theo dõi nhiệt độ. Chọn cách làm mát của bạn.": ("Monitor temperatures. Choose how to cool.", "监控温度，选择散热方式。"),
        "TRỰC TIẾP": ("LIVE", "实时"),
        "Chế độ làm mát": ("Cooling mode", "散热模式"),
        "Chưa bật điều khiển": ("Control not enabled", "尚未启用控制"),
        "Chế độ": ("Mode", "模式"),
        "macOS tự quản lý": ("macOS automatic", "macOS 自动"),
        "Theo nhiệt độ CPU": ("CPU temperature", "按 CPU 温度"),
        "RPM cố định": ("Fixed RPM", "固定转速"),
        "Để macOS tự điều chỉnh quạt": ("Let macOS manage the fan", "由 macOS 自动管理风扇"),
        "Chọn “Theo nhiệt độ CPU” để tùy chỉnh các mốc nhiệt và tốc độ quạt. Thay đổi chỉ có hiệu lực khi bấm Áp dụng.": ("Choose CPU temperature to set the temperature points and fan speeds. Changes take effect when you click Apply.", "选择“按 CPU 温度”以设置温度节点和风扇转速。点击“应用”后更改才会生效。"),
        "Tốc độ mong muốn": ("Target speed", "目标转速"),
        "Mức yêu cầu luôn được giới hạn theo phần cứng. CPU/GPU từ 90°C sẽ ưu tiên quạt tối đa.": ("The target is limited to the hardware range. CPU/GPU temperatures at or above 90°C request maximum speed.", "目标转速限制在硬件范围内。CPU/GPU 达到 90°C 时优先请求最高转速。"),
        "%d–%d RPM · cập nhật mỗi 2 giây": ("%d–%d RPM · updates every 2 seconds", "%d–%d RPM · 每 2 秒更新"),
        "Trả về macOS": ("Return to macOS", "交还 macOS"), "Áp dụng": ("Apply", "应用"),
        "ĐƯỜNG NHIỆT CPU": ("CPU TEMPERATURE CURVE", "CPU 温度曲线"),
        "Êm": ("Quiet", "安静"), "Cân bằng": ("Balanced", "均衡"), "Mát": ("Cool", "凉爽"),
        "MỐC %d": ("POINT %d", "节点 %d"),
        "Nhiệt độ mốc %d": ("Temperature at point %d", "节点 %d 的温度"),
        "Mức quạt mốc %d": ("Fan level at point %d", "节点 %d 的风扇水平"),
        "0% = RPM tối thiểu; 100% = RPM tối đa. Nội suy giữa các mốc; dùng cảm biến CPU nóng nhất.": ("0% = minimum RPM; 100% = maximum RPM. Values are interpolated between points using the hottest CPU sensor.", "0% 为最低转速，100% 为最高转速。节点之间线性插值，使用最高 CPU 传感器温度。"),
        "Nhiệt độ CPU gần đây": ("Recent CPU temperature", "近期 CPU 温度"),
        "Tối đa 3 phút": ("Last 3 minutes", "最近 3 分钟"), "Thời gian": ("Time", "时间"),
        "MacStats cần quyền quản trị để cài bộ điều khiển quạt.": ("MacStats needs administrator access to install the fan controller.", "MacStats 需要管理员权限来安装风扇控制程序。"),
        "MacStats cần quyền quản trị để gỡ bộ điều khiển quạt.": ("MacStats needs administrator access to remove the fan controller.", "MacStats 需要管理员权限来移除风扇控制程序。"),
        "Tệp xác minh chữ ký helper không hợp lệ. Hãy cài lại ứng dụng.": ("The helper signature requirement is invalid. Reinstall the app.", "辅助程序签名验证无效，请重新安装应用。"),
        "Chưa kết nối được bộ trợ giúp. Hãy cài hoặc cập nhật bộ trợ giúp.": ("Cannot connect to the helper. Install or update it.", "无法连接辅助程序，请安装或更新。"),
        "Bộ trợ giúp không phản hồi; đang kết nối lại.": ("Helper is not responding; reconnecting.", "辅助程序无响应，正在重新连接。"),
        "Chỉ theo dõi • Cài bộ trợ giúp để điều khiển quạt.": ("Monitoring only • Install the helper to control the fan.", "仅监控 • 安装辅助程序以控制风扇。"),
        "Chưa đọc được cảm biến CPU M4.": ("Cannot read M4 CPU sensors.", "无法读取 M4 CPU 传感器。"),
        "Phản hồi bộ trợ giúp không hợp lệ.": ("Invalid response from the helper.", "辅助程序响应无效。"),
        "Cài bộ trợ giúp trước khi điều khiển quạt.": ("Install the helper before controlling the fan.", "控制风扇前请安装辅助程序。"),
        "Thao tác chưa hoàn tất.": ("The operation did not finish.", "操作未完成。"),
        "Cho phép MacStats tại Cài đặt hệ thống → Cài đặt chung → Mục đăng nhập.": ("Allow MacStats in System Settings → General → Login Items.", "请在系统设置 → 通用 → 登录项中允许 MacStats。"),
        "Cấu hình RPM không hợp lệ.": ("Invalid RPM configuration.", "转速设置无效。"),
        "Nhiệt độ phải trong 25–90°C; mức quạt trong 0–100%.": ("Temperatures must be 25–90°C and fan levels 0–100%.", "温度必须在 25–90°C，风扇水平必须在 0–100%。"),
        "Nhiệt độ phải tăng dần và mức quạt không được giảm.": ("Temperatures must increase and fan levels must not decrease.", "温度必须递增，风扇水平不得降低。"),
        "Mốc cuối phải đạt 100%.": ("The final point must be 100%.", "最后一个节点必须达到 100%。"),
        "Một cửa sổ MacStats khác đang điều khiển quạt.": ("Another MacStats window is controlling the fan.", "另一个 MacStats 窗口正在控制风扇。"),
        "Đang phục hồi quyền macOS. Hãy thử lại sau.": ("Returning control to macOS. Try again shortly.", "正在交还 macOS 控制，请稍后重试。"),
        "Chưa đọc được cảm biến CPU.": ("Cannot read CPU sensors.", "无法读取 CPU 传感器。"),
        "Quạt đang ở chế độ thủ công của phần mềm khác. Hãy trả quạt về Auto trong phần mềm đó trước.": ("Another app is controlling the fan. Set it to Auto in that app first.", "其他应用正在手动控制风扇，请先在该应用中切换为自动模式。"),
        "Đang thử trả quyền về macOS:": ("Trying to return control to macOS:", "正在尝试交还 macOS 控制："),
        "Mất dữ liệu nhiệt độ CPU M4.": ("M4 CPU temperature data is unavailable.", "M4 CPU 温度数据不可用。"),
        "Mất cảm biến hoặc trạng thái quạt; đã dừng điều khiển.": ("A sensor or fan status was lost; control stopped.", "传感器或风扇状态丢失，已停止控制。"),
        "Giá trị SMC không hợp lệ.": ("Invalid SMC value.", "SMC 值无效。"),
        "RPM vượt giới hạn mã hóa.": ("RPM exceeds the encoding limit.", "转速超出编码限制。"),
        "Giá trị vượt giới hạn.": ("Value exceeds the limit.", "数值超出限制。"),
        "Kích thước dữ liệu SMC sai.": ("Invalid SMC data size.", "SMC 数据大小无效。"),
        "Không tìm thấy AppleSMC.": ("AppleSMC not found.", "找不到 AppleSMC。"),
        "Gói SMC không hợp lệ.": ("Invalid SMC packet.", "SMC 数据包无效。"),
        "Không đọc được số quạt.": ("Cannot read the fan count.", "无法读取风扇数量。"),
        "SMC chưa nhận điều khiển:": ("SMC did not accept control:", "SMC 未接受控制："),
        "đích=": ("target=", "目标="), "yêu cầu=": ("requested=", "请求="),
        "Cấu hình quá lớn.": ("Configuration is too large.", "配置过大。"),
        "Cần quyền quản trị.": ("Administrator access is required.", "需要管理员权限。"),
        "Không xác minh được chữ ký MacStats.": ("Cannot verify the MacStats signature.", "无法验证 MacStats 签名。"),
        "Đường dẫn cài đặt không hợp lệ.": ("Invalid installation path.", "安装路径无效。"),
        "Bộ trợ giúp cũ chưa dừng. Hãy thử lại.": ("The old helper has not stopped. Try again.", "旧辅助程序尚未停止，请重试。"),
        "Bộ trợ giúp chưa dừng.": ("The helper has not stopped.", "辅助程序尚未停止。"),
        "Chưa xác nhận quạt trở về macOS. Đã giữ bộ trợ giúp để thử phục hồi; hãy mở MacStats và thử lại.": ("Fan control has not returned to macOS. The helper was kept to retry recovery; open MacStats and try again.", "尚未确认风扇控制已交还 macOS。已保留辅助程序以重试恢复，请打开 MacStats 后重试。")
    ]
}
