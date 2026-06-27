//
//  SettingsView.swift
//  Eye Break
//
//  职责：提供 Daily Break 设置窗口，以自定义卡片布局承载通用设置、时间安排、休息周期和休息界面。
//  依赖：DailyBreakModel、BreakSettings
//  被使用：MenuBarView（通过系统 Settings scene 弹出设置面板）
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 设置面板视图
///
/// 逻辑：
/// 1. 使用自定义 SwiftUI 卡片和行布局呈现设置页，避免系统 Form 限制视觉还原
/// 2. 通过 @FocusState 管理 TextField 焦点，点击空白区域自动失焦
/// 3. 维护 draftSettings 草稿和 baselineSettings 快照，Save 前不写入 model.settings
/// 4. 每个设置项通过 binding(_:) 读写本地草稿，保存时一次性提交
struct SettingsView: View {
    @ObservedObject var model: DailyBreakModel
    /// 管理数字输入框的焦点状态，点击空白区域可失焦
    @FocusState private var focusedField: Field?
    /// 设置快照，用于检测是否发生变更以及撤销修改
    @State private var baselineSettings: BreakSettings?
    /// 本地设置草稿，用户编辑时只修改草稿，避免未保存内容影响运行中的计时器
    @State private var draftSettings: BreakSettings?
    /// toast 提示消息，非 nil 时在底部浮现
    @State private var toastMessage: String?

    /// 焦点可定位的表单项枚举
    private enum Field: Hashable {
        case workDuration
        case longBreakFrequency
        case longBreakDuration
    }

    /// 当前设置是否与 baseline 不同，驱动保存按钮状态和撤销按钮显示
    private var hasChanges: Bool {
        guard let baseline = baselineSettings, let draft = draftSettings else { return false }
        return draft != baseline
    }

    /// 表单渲染使用的当前草稿；首次渲染前兜底读取 model.settings。
    private var settingsForDisplay: BreakSettings {
        draftSettings ?? model.settings
    }

    /// 设置页可见的重复选项。底层保留 weekdays 兼容旧数据，但设置页不再展示。
    private var settingsPageActiveDays: [ActiveDays] {
        [.everyday, .custom]
    }

    var body: some View {
        ZStack {
            SettingsPalette.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Text("Daily Break 设置")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(SettingsPalette.primaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 18)

                    VStack(spacing: 16) {
                        generalSection
                        scheduleSection
                        cycleSection
                        overlaySection
                    }
                }
                .frame(maxWidth: SettingsLayout.contentWidth)
                .padding(.horizontal, 22)
                .padding(.bottom, hasChanges ? 88 : 20)
            }
        }
        .frame(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            endEditing()
        }
        // 进入设置时保存当前设置作为 baseline，并初始化本地草稿
        .onAppear {
            let settings = normalizedSettingsForSettingsPage(model.settings)
            baselineSettings = settings
            draftSettings = settings
            DispatchQueue.main.async {
                endEditing()
            }
        }
        // 外部设置变化且本页没有未保存修改时，同步刷新草稿
        .onChange(of: model.settings) { newSettings in
            guard !hasChanges else { return }
            let settings = normalizedSettingsForSettingsPage(newSettings)
            baselineSettings = settings
            draftSettings = settings
        }
        // 底部浮层：toast 与保存区共用同一层，避免互相覆盖。
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if let toast = toastMessage {
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SettingsPalette.primaryText)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.62), lineWidth: 1)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if hasChanges {
                    saveBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: SettingsLayout.contentWidth)
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .animation(.easeInOut(duration: 0.2), value: hasChanges)
        .animation(.easeInOut(duration: 0.2), value: toastMessage != nil)
    }

    // MARK: - 分区

    /// 通用设置：开机自启和菜单栏倒计时显示。
    private var generalSection: some View {
        SettingsSectionCard(title: "通用设置", systemImage: "leaf.fill", tint: SettingsPalette.mint) {
            SettingsRow(title: "开机自动启动") {
                settingsToggle(binding(\.launchAtLogin))
            }

            SettingsDivider()

            SettingsRow(title: "菜单栏显示倒计时") {
                settingsToggle(binding(\.menuBarCountdownEnabled))
            }
        }
    }

    /// 时间安排：工作周期、活跃日期、可用时段和午休暂停。
    private var scheduleSection: some View {
        SettingsSectionCard(title: "时间安排", systemImage: "calendar", tint: SettingsPalette.blue) {
            SettingsRow(title: "工作时长") {
                durationField(text: workDurationMinutesBinding, unit: "分钟", field: .workDuration)
            }

            SettingsDivider()

            SettingsRow(title: "重复") {
                SettingsSegmentedControl(
                    selection: repeatDaysBinding,
                    options: settingsPageActiveDays.map { SettingsSegmentOption(value: $0, title: $0.title) },
                    width: SettingsLayout.repeatSegmentedWidth
                )
            }

            if settingsForDisplay.activeDays == .custom {
                SettingsDivider()

                weekdayPicker
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.36))
            }

            SettingsDivider()

            SettingsRow(
                title: "工作可用",
                subtitle: activeWindowBinding.wrappedValue ? activeWindowSubtitle(for: settingsForDisplay) : "全天可用"
            ) {
                settingsToggle(activeWindowBinding)
            }

            if activeWindowBinding.wrappedValue {
                SettingsDivider()

                SettingsRow(title: "开始时间") {
                    timeInlineControl(minuteBinding(\.activeStartMinute))
                }

                SettingsDivider()

                SettingsRow(title: "结束时间") {
                    timeInlineControl(minuteBinding(\.activeEndMinute))
                }
            }

            SettingsDivider()

            SettingsRow(title: "跳过午休") {
                settingsToggle(binding(\.lunchPauseEnabled))
            }

            if settingsForDisplay.lunchPauseEnabled {
                SettingsDivider()

                SettingsRow(title: "午休开始") {
                    timeInlineControl(minuteBinding(\.lunchStartMinute))
                }

                SettingsDivider()

                SettingsRow(title: "午休结束") {
                    timeInlineControl(minuteBinding(\.lunchEndMinute))
                }
            }
        }
    }

    /// 休息周期：短休息时长和长休息周期设置。
    private var cycleSection: some View {
        SettingsSectionCard(title: "休息周期", systemImage: "cup.and.saucer.fill", tint: SettingsPalette.mint) {
            SettingsRow(title: "短休息时长") {
                Picker("", selection: binding(\.shortBreakSeconds)) {
                    Text("20 秒").tag(20)
                    Text("30 秒").tag(30)
                    Text("1 分钟").tag(60)
                    Text("2 分钟").tag(120)
                }
                .pickerStyle(.menu)
                .frame(width: SettingsLayout.menuPickerWidth)
            }

            SettingsDivider()

            SettingsRow(
                title: "长休息设置",
                subtitle: "每 \(settingsForDisplay.longBreakFrequency) 次短休息后进行 1 次长休息"
            ) {
                settingsToggle(binding(\.breakCycleEnabled))
            }

            if settingsForDisplay.breakCycleEnabled {
                SettingsDivider()

                SettingsRow(title: "间隔") {
                    durationField(text: longBreakFrequencyBinding, unit: "次", field: .longBreakFrequency)
                }

                SettingsDivider()

                SettingsRow(title: "长休息时长") {
                    durationField(text: longBreakMinutesBinding, unit: "分钟", field: .longBreakDuration)
                }
            }
        }
    }

    /// 休息界面：蒙层强度和动画开关，保留草稿语义。
    private var overlaySection: some View {
        SettingsSectionCard(title: "休息界面", systemImage: "display", tint: SettingsPalette.lavender) {
            SettingsRow(title: "蒙层强度") {
                SettingsSegmentedControl(
                    selection: binding(\.overlayIntensity),
                    options: OverlayIntensity.allCases.map { SettingsSegmentOption(value: $0, title: $0.shortTitle) },
                    width: SettingsLayout.overlaySegmentedWidth
                )
            }

            SettingsDivider()

            SettingsRow(title: "动画效果") {
                settingsToggle(binding(\.animationEnabled))
            }
        }
    }

    /// 底部保存区：仅有未保存修改时显示，固定浮在窗口底部。
    private var saveBar: some View {
        HStack(spacing: 12) {
            Button("撤销") {
                endEditing()
                undoChanges()
            }
            .buttonStyle(SettingsSecondaryButtonStyle())

            Spacer()

            Button("保存") {
                endEditing()
                DispatchQueue.main.async {
                    saveChanges()
                }
            }
            .buttonStyle(SettingsSaveButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.66), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
    }

    /// 自定义星期选择器，横向排列为轻量复选按钮。
    private var weekdayPicker: some View {
        HStack(spacing: 5) {
            ForEach(weekdayOptions, id: \.value) { option in
                WeekdayToggle(title: option.title, isOn: customWeekdayBinding(option.value))
            }
        }
    }

    // MARK: - 控件构造

    /// 创建带单位胶囊的数字输入框。
    ///
    /// 逻辑：
    /// 1. TextField 只展示数值，由外部 Binding 负责过滤和换算
    /// 2. 单位作为右侧胶囊提示，保持行内控件紧凑
    private func durationField(text: Binding<String>, unit: String, field: Field) -> some View {
        let isFocused = focusedField == field

        return HStack(spacing: 8) {
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(SettingsPalette.primaryText)
                .focused($focusedField, equals: field)
                .frame(width: SettingsLayout.numericTextWidth)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isFocused ? SettingsPalette.teal.opacity(0.95) : SettingsPalette.separator.opacity(0.8),
                            lineWidth: isFocused ? 1.4 : 1
                        )
                }
                .shadow(
                    color: isFocused ? SettingsPalette.teal.opacity(0.18) : .clear,
                    radius: isFocused ? 6 : 0,
                    x: 0,
                    y: 0
                )

            Text(unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SettingsPalette.secondaryText)
                .frame(width: SettingsLayout.unitWidth, alignment: .center)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(SettingsPalette.blue.opacity(0.12), in: Capsule())
        }
    }

    /// 创建 24 小时制行内时间控件。
    ///
    /// 逻辑：
    /// 1. 展示 HH:mm，不显示 AM/PM 或上午下午
    /// 2. 非法输入回滚到上一次合法值，并显示 toast
    /// 3. 控件整体进入统一右侧控制列，保持行尾视觉对齐
    private func timeInlineControl(_ minuteBinding: Binding<Int>) -> some View {
        TimeInlineControl(minuteOfDay: minuteBinding) {
            toastMessage = "请输入 4 位 24 小时制时间，如 0900 或 1830。"
            dismissToastAfterDelay()
        }
            .frame(width: SettingsLayout.timeInlineWidth)
    }

    /// 生成工作可用时间窗口说明文案。
    ///
    /// 逻辑：
    /// 1. 结束时间大于开始时间：显示当天时间段
    /// 2. 结束时间小于开始时间：显示跨天时间段
    /// 3. 两者相等：提示不能保存，避免用户误解为全天
    private func activeWindowSubtitle(for settings: BreakSettings) -> String {
        let start = timeLabel(settings.activeStartMinute)
        let end = timeLabel(settings.activeEndMinute)
        if settings.activeStartMinute == settings.activeEndMinute {
            return "24 小时制，开始和结束时间不能相同"
        }
        if settings.activeEndMinute < settings.activeStartMinute {
            return "24 小时制，当前仅在 \(start) - 次日 \(end) 生效"
        }
        return "24 小时制，当前仅在 \(start) - \(end) 生效"
    }

    /// 创建标准开关控件，统一系统 Toggle 在右侧槽位里的可见边界。
    ///
    /// 逻辑：所有设置页 Toggle 都通过同一宽度进入 control slot，避免系统控件内部尺寸差异造成视觉右边缘不齐。
    private func settingsToggle(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .frame(width: SettingsLayout.toggleWidth, alignment: .trailing)
    }

    // MARK: - 操作

    /// 结束所有输入框编辑，用于点击空白处、保存前、撤销前统一失焦。
    private func endEditing() {
        focusedField = nil

        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }

    /// 撤销所有未保存的修改，恢复本地草稿到 baseline 快照
    ///
    /// 逻辑：
    /// 1. 从 baselineSettings 取出快照覆盖 draftSettings
    /// 2. 不写入 model.settings，确保撤销未保存内容不会触发持久化
    /// 3. 显示"已取消修改"的 toast 提示，2.5 秒后自动消失
    private func undoChanges() {
        guard let baseline = baselineSettings else { return }
        draftSettings = baseline
        toastMessage = "已取消修改"
        dismissToastAfterDelay()
    }

    /// 保存当前草稿设置，将当前值更新为新的 baseline
    ///
    /// 逻辑：
    /// 1. 将 draftSettings 一次性写入 model.settings，触发持久化和 engine 同步
    /// 2. 用保存后的值覆盖 baselineSettings，hasChanges 变为 false
    private func saveChanges() {
        guard let draft = draftSettings else { return }
        if isActiveWindowEnabled(draft), draft.activeStartMinute == draft.activeEndMinute {
            toastMessage = "开始和结束时间不能相同"
            dismissToastAfterDelay()
            return
        }
        model.settings = draft
        baselineSettings = draft
        draftSettings = draft
    }

    /// 判断工作可用时间窗口是否处于开启状态。
    private func isActiveWindowEnabled(_ settings: BreakSettings) -> Bool {
        !(settings.activeStartMinute == 0 && settings.activeEndMinute == 24 * 60)
    }

    /// 延迟 2.5 秒后清除 toast 消息
    private func dismissToastAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            toastMessage = nil
        }
    }

    // MARK: - Binding

    /// 创建 BreakSettings 草稿属性与 Toggle/Picker 之间的双向绑定
    ///
    /// 逻辑：
    /// 1. get 从 draftSettings 读取属性，草稿未初始化时回退到 model.settings
    /// 2. set 只写入 draftSettings，不影响运行中的 model.settings
    /// - Parameter keyPath: BreakSettings 的可写键路径
    private func binding<Value>(_ keyPath: WritableKeyPath<BreakSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsForDisplay[keyPath: keyPath] },
            set: { value in
                var draft = settingsForDisplay
                draft[keyPath: keyPath] = value
                draftSettings = draft
            }
        )
    }

    /// 设置页重复选项绑定，只暴露“每天 / 自定义”。
    ///
    /// 逻辑：
    /// 1. 历史保存的 weekdays 在设置页按 everyday 展示
    /// 2. 用户保存后只会写回 everyday 或 custom，避免再次产生隐藏选项
    private var repeatDaysBinding: Binding<ActiveDays> {
        Binding(
            get: {
                settingsForDisplay.activeDays == .custom ? .custom : .everyday
            },
            set: { value in
                var draft = settingsForDisplay
                draft.activeDays = value
                draftSettings = draft
            }
        )
    }

    /// 将历史配置归一化为设置页当前支持的可见选项。
    ///
    /// 逻辑：底层保留 weekdays 兼容旧数据；设置页打开时统一映射为 everyday，避免分段控件出现不可见选中项。
    private func normalizedSettingsForSettingsPage(_ settings: BreakSettings) -> BreakSettings {
        var normalized = settings
        if normalized.activeDays == .weekdays {
            normalized.activeDays = .everyday
        }
        return normalized
    }

    /// 工作可用开关绑定，用于在不新增模型字段的前提下控制时间窗口是否启用。
    ///
    /// 逻辑：
    /// 1. 当前时间窗口覆盖 00:00-24:00 时视为关闭限制
    /// 2. 开启时若原先为全天窗口，则恢复默认 09:00-18:00
    /// 3. 关闭时把窗口写为全天，仍不改变 activeDays 的日期规则
    private var activeWindowBinding: Binding<Bool> {
        Binding(
            get: {
                !(settingsForDisplay.activeStartMinute == 0 && settingsForDisplay.activeEndMinute == 24 * 60)
            },
            set: { isOn in
                var draft = settingsForDisplay
                if isOn {
                    if draft.activeStartMinute == 0 && draft.activeEndMinute == 24 * 60 {
                        draft.activeStartMinute = BreakSettings.defaults.activeStartMinute
                        draft.activeEndMinute = BreakSettings.defaults.activeEndMinute
                    }
                } else {
                    draft.activeStartMinute = 0
                    draft.activeEndMinute = 24 * 60
                }
                draftSettings = draft
            }
        )
    }

    /// 分钟数 Int 绑定，用于时间胶囊按钮直接读写 minuteOfDay
    ///
    /// 逻辑：
    /// 1. get: 从 draftSettings 读取 keyPath 对应的分钟数
    /// 2. set: 将新分钟数写回 draftSettings
    private func minuteBinding(_ keyPath: WritableKeyPath<BreakSettings, Int>) -> Binding<Int> {
        Binding(
            get: { settingsForDisplay[keyPath: keyPath] },
            set: { value in
                var draft = settingsForDisplay
                draft[keyPath: keyPath] = value
                draftSettings = draft
            }
        )
    }

    /// 工作时长（分钟）的字符串绑定，用于 TextField
    ///
    /// 逻辑：
    /// 1. get: 将 workDurationSeconds 转为分钟，取整显示，最少 1
    /// 2. set: 过滤非数字字符，解析为分钟数并转回秒数写入
    /// 3. 无效输入（非正数）时忽略写入
    private var workDurationMinutesBinding: Binding<String> {
        Binding(
            get: { "\(max(1, settingsForDisplay.workDurationSeconds / 60))" },
            set: { value in
                let digits = value.filter(\.isNumber)
                guard let minutes = Int(digits), minutes > 0 else { return }
                var draft = settingsForDisplay
                draft.workDurationSeconds = minutes * 60
                draftSettings = draft
            }
        )
    }

    /// 长休息间隔次数的字符串绑定，用于 TextField。
    ///
    /// 逻辑：
    /// 1. get: 读取 longBreakFrequency，至少显示 1
    /// 2. set: 仅保留数字，写入正整数，避免下拉选项限制用户输入
    private var longBreakFrequencyBinding: Binding<String> {
        Binding(
            get: { "\(max(1, settingsForDisplay.longBreakFrequency))" },
            set: { value in
                let digits = value.filter(\.isNumber)
                guard let count = Int(digits), count > 0 else { return }
                var draft = settingsForDisplay
                draft.longBreakFrequency = count
                draftSettings = draft
            }
        )
    }

    /// 长休息分钟数的字符串绑定，用于 TextField。
    ///
    /// 逻辑：
    /// 1. get: 将 longBreakSeconds 换算成分钟，至少显示 1
    /// 2. set: 仅保留整数分钟，再换算成秒写回草稿
    private var longBreakMinutesBinding: Binding<String> {
        Binding(
            get: { "\(max(1, settingsForDisplay.longBreakSeconds / 60))" },
            set: { value in
                let digits = value.filter(\.isNumber)
                guard let minutes = Int(digits), minutes > 0 else { return }
                var draft = settingsForDisplay
                draft.longBreakSeconds = minutes * 60
                draftSettings = draft
            }
        )
    }

    /// 自定义工作日选项列表：显示名称与 Calendar 星期值对应
    ///
    /// Calendar 中周日 = 1，周一 = 2，... 周六 = 7
    private var weekdayOptions: [(title: String, value: Int)] {
        [
            ("周一", 2),
            ("周二", 3),
            ("周三", 4),
            ("周四", 5),
            ("周五", 6),
            ("周六", 7),
            ("周日", 1)
        ]
    }

    /// 自定义工作日的勾选框绑定
    ///
    /// 逻辑：
    /// 1. get: 检查 weekday 是否在 customActiveWeekdays 集合中
    /// 2. set: 勾选时插入 weekday，取消时从集合中移除
    /// - Parameter weekday: Calendar 星期值（1-7）
    private func customWeekdayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { settingsForDisplay.customActiveWeekdays.contains(weekday) },
            set: { isOn in
                var draft = settingsForDisplay
                if isOn {
                    draft.customActiveWeekdays.insert(weekday)
                } else {
                    draft.customActiveWeekdays.remove(weekday)
                }
                draftSettings = draft
            }
        )
    }

    /// 将分钟数格式化为 24 小时制 HH:mm，用于 subtitle 和行内时间控件。
    private func timeLabel(_ minute: Int) -> String {
        let clamped = min(max(minute, 0), 24 * 60 - 1)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}

// MARK: - 设置页子组件

/// 设置页分区卡片，包含图标标题和内部行容器。
private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(SettingsPalette.primaryText)
            }

            VStack(spacing: 0) {
                content
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(.white.opacity(0.44), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.54), lineWidth: 1)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.68), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.055), radius: 12, x: 0, y: 7)
    }
}

/// 设置项行，左侧固定标题，右侧放置具体控件。
private struct SettingsRow<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsPalette.primaryText)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(SettingsPalette.secondaryText)
                        .lineLimit(1)
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)

            SettingsControlSlot {
                content
                    .tint(SettingsPalette.teal)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: SettingsLayout.rowHeight)
        .background(.white.opacity(0.36))
    }
}

/// 设置页自绘分段控件，避免系统 segmented picker 的内部 padding 破坏视觉右对齐。
private struct SettingsSegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }
}

/// 自绘分段控件，控件可见背景等于 frame 边界，便于在 control slot 内精确右对齐。
private struct SettingsSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SettingsSegmentOption<Value>]
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    ZStack {
                        if selection == option.value {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(SettingsPalette.teal)
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.clear)
                        }

                        Text(option.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                selection == option.value
                                ? .white
                                : SettingsPalette.primaryText.opacity(0.74)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: SettingsLayout.segmentedHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .frame(width: width, height: SettingsLayout.segmentedHeight + 4)
        .background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SettingsPalette.separator.opacity(0.65), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

/// 统一右侧控件槽，负责把主要控件推到同一个右侧视觉基准线。
private struct SettingsControlSlot<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            content
                .fixedSize()
        }
        .frame(width: SettingsLayout.controlColumnWidth, alignment: .trailing)
    }
}

/// 分区内部浅色分割线。
private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsPalette.separator)
            .frame(height: 1)
            .padding(.leading, 20)
    }
}

/// 自定义星期复选按钮。
private struct WeekdayToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isOn ? SettingsPalette.teal : SettingsPalette.secondaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(
                isOn ? SettingsPalette.teal.opacity(0.13) : .white.opacity(0.42),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isOn ? SettingsPalette.teal.opacity(0.32) : SettingsPalette.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// 保存按钮样式，只在有变更时出现，因此不再承载禁用态。
private struct SettingsSaveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 124, height: 36)
            .background(
                SettingsPalette.teal.opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .shadow(color: SettingsPalette.teal.opacity(0.24), radius: 10, x: 0, y: 6)
    }
}

/// 撤销按钮样式，保持次级但可见。
private struct SettingsSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SettingsPalette.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                .white.opacity(configuration.isPressed ? 0.42 : 0.58),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.62), lineWidth: 1)
            }
    }
}

/// 行内时间控件：4 位数字输入 mask，自动展示为 24 小时制 HH:mm。
///
/// 逻辑：
/// 1. 用户只输入数字，控件自动将 0900 展示为 09:00
/// 2. 输入提交或失焦时解析，非法输入回滚到上一次合法值并回调提示
/// 3. 展示层使用 24 小时制，存储层仍然是 0...1439 的 minuteOfDay
private struct TimeInlineControl: View {
    @Binding var minuteOfDay: Int
    var onInvalidInput: () -> Void

    @State private var text: String = ""
    @State private var lastValidMinute: Int = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: timeTextBinding)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettingsPalette.primaryText)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .frame(width: SettingsLayout.timeTextWidth, height: 24)
                .onSubmit {
                    commitText()
                    isFocused = false
                }

            VStack(spacing: 0) {
                Button {
                    step(minutes: 1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 12)

                Button {
                    step(minutes: -1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 12)
            }
            .foregroundStyle(SettingsPalette.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: SettingsLayout.timeInlineWidth)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isFocused ? SettingsPalette.teal.opacity(0.95) : SettingsPalette.separator.opacity(0.8),
                    lineWidth: isFocused ? 1.4 : 1
                )
        }
        .shadow(
            color: isFocused ? SettingsPalette.teal.opacity(0.18) : .clear,
            radius: isFocused ? 6 : 0,
            x: 0,
            y: 0
        )
        .onAppear {
            lastValidMinute = clampedMinute(minuteOfDay)
            text = formatted(lastValidMinute)
        }
        .onChange(of: minuteOfDay) { newValue in
            let clamped = clampedMinute(newValue)
            lastValidMinute = clamped
            guard !isFocused else { return }
            text = formatted(clamped)
        }
        .onChange(of: isFocused) { focused in
            if focused {
                lastValidMinute = clampedMinute(minuteOfDay)
                text = formatted(lastValidMinute)
            } else if text != formatted(clampedMinute(minuteOfDay)) {
                commitText()
            }
        }
    }

    /// 时间文本绑定：只接受数字输入，冒号由控件自动补齐。
    private var timeTextBinding: Binding<String> {
        Binding(
            get: { text },
            set: { value in
                text = formattedInputText(value)
            }
        )
    }

    /// 输入时自动补冒号：0900 -> 09:00，1830 -> 18:30。
    private func formattedInputText(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber).prefix(4))

        guard digits.count > 2 else {
            return digits
        }

        let hour = digits.prefix(2)
        let minute = digits.dropFirst(2)

        return "\(hour):\(minute)"
    }

    /// 按指定分钟数循环步进。
    private func step(minutes: Int) {
        commitIfNeededBeforeStepping()
        let total = 24 * 60
        minuteOfDay = (minuteOfDay + minutes + total) % total
        lastValidMinute = clampedMinute(minuteOfDay)
        text = formatted(lastValidMinute)
    }

    /// 步进前先提交当前文本，避免用户输入合法值后直接点箭头时丢失输入。
    private func commitIfNeededBeforeStepping() {
        guard isFocused else { return }
        if let parsed = parse(text) {
            minuteOfDay = parsed
            lastValidMinute = parsed
        } else {
            rollbackInvalidInput()
        }
    }

    /// 提交当前文本，非法输入回滚到上一次合法值。
    private func commitText() {
        if let parsed = parse(text) {
            minuteOfDay = parsed
            lastValidMinute = parsed
            text = formatted(parsed)
        } else {
            rollbackInvalidInput()
        }
    }

    /// 回滚非法输入并通知外层显示提示。
    private func rollbackInvalidInput() {
        minuteOfDay = lastValidMinute
        text = formatted(lastValidMinute)
        onInvalidInput()
    }

    /// 解析 4 位数字时间：0900 / 1830，同时兼容已格式化后的 09:00 / 18:30。
    private func parse(_ value: String) -> Int? {
        let digits = String(value.filter(\.isNumber).prefix(4))

        guard digits.count == 4 else {
            return nil
        }

        let hourText = String(digits.prefix(2))
        let minuteText = String(digits.suffix(2))

        guard let hour = Int(hourText),
              let minute = Int(minuteText),
              (0..<24).contains(hour),
              (0..<60).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }

    /// 格式化为 24 小时制 HH:mm。
    private func formatted(_ minute: Int) -> String {
        let clamped = clampedMinute(minute)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// 将分钟数限制在一天内，避免外部异常值影响展示。
    private func clampedMinute(_ minute: Int) -> Int {
        min(max(minute, 0), 24 * 60 - 1)
    }
}

/// 设置页布局常量，集中约束窗口宽度、内容宽度和右侧控制列。
enum SettingsLayout {
    static let windowWidth: CGFloat = 690
    static let windowHeight: CGFloat = 690
    static let contentWidth: CGFloat = 590
    static let controlColumnWidth: CGFloat = 260
    static let rowHeight: CGFloat = 42
    static let numericTextWidth: CGFloat = 44
    static let unitWidth: CGFloat = 28
    static let timeInlineWidth: CGFloat = 102
    static let timeTextWidth: CGFloat = 62
    static let toggleWidth: CGFloat = 58
    static let menuPickerWidth: CGFloat = 130
    static let repeatSegmentedWidth: CGFloat = 164
    static let overlaySegmentedWidth: CGFloat = 190
    static let segmentedHeight: CGFloat = 30
}

/// 设置页局部色板，避免污染全局颜色命名。
private enum SettingsPalette {
    static let primaryText = Color(red: 0.13, green: 0.22, blue: 0.30)
    static let secondaryText = Color(red: 0.38, green: 0.48, blue: 0.56)
    static let blue = Color(red: 0.35, green: 0.60, blue: 0.88)
    static let mint = Color(red: 0.36, green: 0.75, blue: 0.65)
    static let teal = Color(red: 0.18, green: 0.68, blue: 0.62)
    static let lavender = Color(red: 0.58, green: 0.55, blue: 0.88)
    static let separator = Color(red: 0.78, green: 0.84, blue: 0.88).opacity(0.55)

    static var background: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.94, green: 0.98, blue: 0.99),
                Color(red: 0.89, green: 0.96, blue: 0.94),
                Color(red: 0.95, green: 0.94, blue: 0.99)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// 设置页使用的短标题，避免把模型显示文案改成页面专用文案。
private extension OverlayIntensity {
    var shortTitle: String {
        switch self {
        case .light: "弱"
        case .medium: "中"
        case .strong: "强"
        }
    }
}
