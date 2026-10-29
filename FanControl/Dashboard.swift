import SwiftUI
import Charts

private let teal = Color(red: 0.34, green: 0.88, blue: 0.76)
@available(macOS 14.0, *)
struct FanDashboard: View {
    @ObservedObject var model: FanAppModel
    @State private var removeConfirmation = false
    private var firstFan: FanReading? { model.snapshot.fans.first }
    private var minimum: Double { firstFan?.minimum ?? 1000 }
    private var maximum: Double { firstFan?.maximum ?? 4900 }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    HStack(spacing: 14) {
                        metric(model.language.text("NHIỆT ĐỘ CPU"), value: model.snapshot.cpuTemperature.map { String(format: "%.1f", $0) } ?? "—", unit: "°C", symbol: "cpu", tint: teal)
                        metric(model.language.text("TỐC ĐỘ QUẠT"), value: firstFan.map { "\(Int($0.actual))" } ?? "—", unit: "RPM", symbol: "fanblades", tint: .cyan)
                        metric(model.language.text("NHIỆT ĐỘ GPU"), value: model.snapshot.gpuTemperature.map { String(format: "%.1f", $0) } ?? "—", unit: "°C", symbol: "square.3.layers.3d", tint: .orange)
                    }
                    if let error = model.error ?? model.snapshot.error {
                        Label(model.language.message(error), systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(model.snapshot.fans) { fan in
                        HStack {
                            Text(model.language.format("Quạt %d: %d RPM", fan.id + 1, Int(fan.actual)))
                            Spacer()
                            Text(fan.target.map { String(format: "→ %.0f RPM", $0) } ?? "—").foregroundStyle(.secondary)
                        }.font(.caption.monospacedDigit())
                    }
                    Text(model.language.message(model.snapshot.message)).font(.caption).foregroundStyle(.secondary)
                    controls
                    history
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled").foregroundStyle(teal)
                        Text(model.language.text("CPU/GPU từ 90°C: yêu cầu quạt tối đa. Khi thoát, mất kết nối hoặc mất cảm biến: trả quyền cho macOS. Đóng cửa sổ vẫn chạy ở thanh menu.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(28)
            }
        }
        .background(Color(red: 0.065, green: 0.075, blue: 0.09))
        .tint(teal)
        .alert(model.language.text("Gỡ bộ trợ giúp MacStats?"), isPresented: $removeConfirmation) {
            Button(model.language.text("Hủy"), role: .cancel) {}
            Button(model.language.text("Gỡ"), role: .destructive) { model.restore { model.installHelper(remove: true) } }
        } message: { Text(model.language.text("Quạt được trả về macOS. Bạn vẫn có thể theo dõi nhiệt độ và cài lại bộ trợ giúp sau.")) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                Image(systemName: "fanblades.fill").font(.system(size: 29)).foregroundStyle(teal)
                VStack(alignment: .leading, spacing: 2) { Text("MacStats").font(.title2.bold()); Text(model.language.text("MÁT HƠN. CHỦ ĐỘNG HƠN.")).font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(.secondary) }
            }
            Label(model.language.text("Điều khiển quạt"), systemImage: "slider.horizontal.3").font(.callout.weight(.medium)).foregroundStyle(teal).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 13) {
                Text(model.language.text("KHỞI ĐỘNG")).font(.caption2.bold()).foregroundStyle(.secondary).tracking(1)
                Toggle(model.language.text("Tự bật đường nhiệt khi mở"), isOn: $model.startCurve).font(.caption)
                Text(model.language.text("Chỉ bật khi bạn đã chọn và áp dụng đường nhiệt phù hợp.")).font(.caption2).foregroundStyle(.secondary)
            }.toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.language.text("Ngôn ngữ")).font(.caption2.bold()).foregroundStyle(.secondary)
                Picker(model.language.text("Ngôn ngữ"), selection: $model.language) {
                    ForEach(FanLanguage.allCases) { language in Text(language.name).tag(language) }
                }.labelsHidden().accessibilityLabel(Text(model.language.text("Ngôn ngữ")))
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack { Circle().fill(model.connected ? teal : .orange).frame(width: 7, height: 7); Text(model.language.text(model.connected ? "Bộ trợ giúp đã kết nối" : "Chế độ theo dõi")).font(.caption) }
                Button(model.language.text(model.helperInstalled ? "Cập nhật bộ trợ giúp" : "Cài bộ trợ giúp")) { model.installHelper() }.disabled(model.busy).frame(maxWidth: .infinity)
                if model.helperInstalled { Button(model.language.text("Gỡ bộ trợ giúp…")) { removeConfirmation = true }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.busy) }
                Text(model.language.text("Yêu cầu quyền quản trị để điều khiển quạt.")).font(.caption2).foregroundStyle(.secondary)
                Divider().padding(.vertical, 8)
                Text("Apple M4").font(.caption.weight(.medium))
                Text(model.language.text("MacStats · Chạy hoàn toàn trên máy")).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(22).frame(width: 220).background(.white.opacity(0.025))
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.language.text("Kiểm soát luồng gió.")).font(.system(size: 29, weight: .semibold))
                Text(model.language.text("Theo dõi nhiệt độ. Chọn cách làm mát của bạn.")).foregroundStyle(.secondary).font(.callout)
            }
            Spacer()
            HStack(spacing: 5) { Circle().fill(model.snapshot.error == nil ? teal : .orange).frame(width: 6, height: 6); Text(model.language.text("TRỰC TIẾP")).font(.system(size: 9, weight: .bold)).tracking(1) }.padding(.horizontal, 10).padding(.vertical, 7).background(teal.opacity(0.08), in: Capsule())
        }
    }
    private func metric(_ title: String, value: String, unit: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(title).font(.system(size: 9, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary); Spacer(); Image(systemName: symbol).foregroundStyle(tint) }
            HStack(alignment: .firstTextBaseline, spacing: 4) { Text(value).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit(); Text(unit).font(.caption).foregroundStyle(.secondary) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(model.language.text("Chế độ làm mát")).font(.headline)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.language.text(model.connected ? model.snapshot.mode.title : "Chưa bật điều khiển")).font(.caption).foregroundStyle(teal)
            }
            Picker(model.language.text("Chế độ"), selection: $model.draft.mode) { ForEach(ControlMode.allCases, id: \.self) { Text(model.language.text($0.title)).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            switch model.draft.mode {
            case .system:
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.language.text("Để macOS tự điều chỉnh quạt"), systemImage: "apple.logo").font(.title3.weight(.medium))
                    Text(model.language.text("Chọn “Theo nhiệt độ CPU” để tùy chỉnh các mốc nhiệt và tốc độ quạt. Thay đổi chỉ có hiệu lực khi bấm Áp dụng.")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
            case .manual:
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text(model.language.text("Tốc độ mong muốn")); Spacer(); Text("\(Int(model.draft.manualRPM)) RPM").font(.title2.monospacedDigit()).foregroundStyle(teal) }
                    Slider(value: $model.draft.manualRPM, in: minimum...maximum, step: 50).accessibilityLabel(model.language.text("RPM cố định"))
                    HStack { Text("\(Int(minimum)) RPM"); Spacer(); Text("\(Int(maximum)) RPM") }.font(.caption).foregroundStyle(.secondary)
                    Text(model.language.text("Mức yêu cầu luôn được giới hạn theo phần cứng. CPU/GPU từ 90°C sẽ ưu tiên quạt tối đa.")).font(.caption).foregroundStyle(.secondary)
                }.frame(minHeight: 160)
            case .curve: curveEditor
            }
            Divider()
            HStack {
                Text(model.language.format("%d–%d RPM · cập nhật mỗi 2 giây", Int(minimum), Int(maximum))).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.language.text("Trả về macOS")) { model.restore() }.disabled(!model.connected || model.busy)
                Button(model.language.text("Áp dụng")) { model.apply() }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(!model.connected || model.busy)
            }
        }.padding(20).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }
    private var curveEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.language.text("ĐƯỜNG NHIỆT CPU")).font(.caption2.bold()).foregroundStyle(.secondary).tracking(1)
                Spacer()
                ForEach(["Êm", "Cân bằng", "Mát"], id: \.self) { name in Button(model.language.text(name)) { model.preset(name) }.font(.caption).buttonStyle(.bordered) }
            }
            Chart {
                ForEach(Array(model.draft.points.enumerated()), id: \.offset) { _, point in
                    AreaMark(x: .value("°C", point.temperature), yStart: .value("RPM", minimum), yEnd: .value("RPM", minimum + point.percent / 100 * (maximum - minimum))).foregroundStyle(LinearGradient(colors: [teal.opacity(0.2), teal.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("°C", point.temperature), y: .value("RPM", minimum + point.percent / 100 * (maximum - minimum))).foregroundStyle(teal).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("°C", point.temperature), y: .value("RPM", minimum + point.percent / 100 * (maximum - minimum))).foregroundStyle(teal).symbolSize(45)
                }
                if let cpu = model.snapshot.cpuTemperature { RuleMark(x: .value("CPU", cpu)).foregroundStyle(.white.opacity(0.35)).lineStyle(StrokeStyle(dash: [4, 4])) }
            }.chartXScale(domain: 25...95).chartYScale(domain: minimum...maximum).chartXAxis { AxisMarks(values: [30, 45, 60, 75, 90]) { axis in AxisGridLine(); AxisValueLabel { Text("\(Int(axis.as(Double.self) ?? 0))°") } } }.frame(height: 130)
            HStack(spacing: 10) {
                ForEach(model.draft.points.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.language.format("MỐC %d", index + 1)).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        HStack(spacing: 3) { TextField("°C", value: $model.draft.points[index].temperature, format: .number).accessibilityLabel(Text(model.language.format("Nhiệt độ mốc %d", index + 1))); Text("°C").foregroundStyle(.secondary) }.textFieldStyle(.roundedBorder)
                        HStack(spacing: 3) { TextField("%", value: $model.draft.points[index].percent, format: .number).disabled(index == model.draft.points.count - 1).accessibilityLabel(Text(model.language.format("Mức quạt mốc %d", index + 1))); Text("%").foregroundStyle(.secondary) }.textFieldStyle(.roundedBorder)
                    }.font(.caption).padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Text(model.language.text("0% = RPM tối thiểu; 100% = RPM tối đa. Nội suy giữa các mốc; dùng cảm biến CPU nóng nhất.")).font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(model.language.text("Nhiệt độ CPU gần đây")).font(.callout.weight(.medium)); Spacer(); Text(model.language.text("Tối đa 3 phút")).font(.caption2).foregroundStyle(.secondary) }
            Chart(model.history) { sample in
                LineMark(x: .value(model.language.text("Thời gian"), sample.date), y: .value("CPU", sample.cpu)).foregroundStyle(teal).interpolationMethod(.linear)
            }.chartYScale(domain: 20...110).chartXAxis(.hidden).frame(height: 75)
        }.padding(18).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
    }
}
