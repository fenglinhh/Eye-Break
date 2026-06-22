import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: DailyBreakModel

    var body: some View {
        Form {
            Section("通用设置") {
                Toggle("开机自动启动", isOn: binding(\.launchAtLogin))
                Toggle("菜单栏显示倒计时", isOn: binding(\.menuBarCountdownEnabled))
                Toggle("播放提醒声音", isOn: binding(\.playSound))
            }

            Section("时间安排") {
                Picker("生效日期", selection: binding(\.activeDays)) {
                    ForEach(ActiveDays.allCases) { day in
                        Text(day.title).tag(day)
                    }
                }
                Picker("开始时间", selection: binding(\.activeStartMinute)) {
                    timeOptions
                }
                Picker("结束时间", selection: binding(\.activeEndMinute)) {
                    timeOptions
                }
                Toggle("午休暂停", isOn: binding(\.lunchPauseEnabled))
                Picker("午休开始", selection: binding(\.lunchStartMinute)) {
                    timeOptions
                }
                Picker("午休结束", selection: binding(\.lunchEndMinute)) {
                    timeOptions
                }
            }

            Section("休息周期") {
                Picker("工作时长", selection: binding(\.workDurationSeconds)) {
                    durationOptions([10, 15, 20, 25, 30, 45, 60], unit: 60, suffix: "分钟")
                }
                Picker("短休息时长", selection: binding(\.shortBreakSeconds)) {
                    Text("20 秒").tag(20)
                    Text("30 秒").tag(30)
                    Text("1 分钟").tag(60)
                    Text("2 分钟").tag(120)
                }
                Picker("长休息时长", selection: binding(\.longBreakSeconds)) {
                    durationOptions([3, 5, 10], unit: 60, suffix: "分钟")
                }
                Picker("长休息触发频率", selection: binding(\.longBreakFrequency)) {
                    ForEach([2, 3, 4, 5], id: \.self) { count in
                        Text("每 \(count) 次短休息").tag(count)
                    }
                }
            }

            Section("休息界面") {
                Picker("蒙层强度", selection: binding(\.overlayIntensity)) {
                    ForEach(OverlayIntensity.allCases) { intensity in
                        Text(intensity.title).tag(intensity)
                    }
                }
                Toggle("动画效果", isOn: binding(\.animationEnabled))
                Toggle("显示健康建议", isOn: binding(\.healthTipsEnabled))
                Toggle("允许跳过休息", isOn: binding(\.allowSkip))
            }

            Section("通知设置") {
                Toggle("提前 30 秒提醒", isOn: binding(\.preBreakNotificationEnabled))
                Toggle("显示 Dock 图标提醒", isOn: binding(\.showDockReminder))
            }

            Section("高级设置") {
                Toggle("锁屏时暂停计时", isOn: binding(\.pauseOnLock))
                Toggle("长时间离开后重置计时", isOn: binding(\.resetAfterLongAway))
                Text("会议、屏幕共享、麦克风和摄像头自动识别将在后续版本评估。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 680)
    }

    private var timeOptions: some View {
        ForEach(stride(from: 0, through: 23 * 60 + 30, by: 30).map { $0 }, id: \.self) { minute in
            Text(timeLabel(minute)).tag(minute)
        }
    }

    private func durationOptions(_ values: [Int], unit: Int, suffix: String) -> some View {
        ForEach(values, id: \.self) { value in
            Text("\(value) \(suffix)").tag(value * unit)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<BreakSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.settings[keyPath: keyPath] = $0 }
        )
    }

    private func timeLabel(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}
