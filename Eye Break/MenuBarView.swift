import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: DailyBreakModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.statusLine)
                    .font(.headline)
                Text("短休息 \(model.todayShortBreaks) 次 · 长休息 \(model.todayLongBreaks) 次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if model.phase == .paused {
                Button("恢复计时") {
                    performAndClose(model.resume)
                }
            } else {
                Button("暂停 30 分钟") {
                    performAndClose(model.pauseThirtyMinutes)
                }
            }

            Button("立即休息") {
                performAndClose(model.startBreakNow)
            }
            Button("跳过本次休息") {
                performAndClose(model.skipBreak)
            }
                .disabled(!model.settings.allowSkip)
            Button("延后 1 分钟") {
                performAndClose(model.postponeOneMinute)
            }
                .disabled(!model.canPostponeBreak)
            Button("暂停至明天") {
                performAndClose(model.pauseUntilTomorrow)
            }

            Divider()

            Button("打开设置") {
                openSettings()
                NSApplication.shared.activate(ignoringOtherApps: true)
                closeMenuWindow()
            }
            Button("退出 Daily Break") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 260)
        .overlay(alignment: .bottom) {
            if let toast = model.toastMessage {
                Text(toast)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 4)
            }
        }
    }

    private func performAndClose(_ action: @escaping () -> Void) {
        closeMenuWindow()
        DispatchQueue.main.async {
            action()
        }
    }

    private func closeMenuWindow() {
        dismiss()
        DispatchQueue.main.async {
            NSApplication.shared.keyWindow?.performClose(nil)
        }
    }
}
