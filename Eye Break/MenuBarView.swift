//
//  MenuBarView.swift
//  Eye Break
//
//  职责：菜单栏弹出面板的主视图，展示状态、健康提示、操作按钮和 Toast 消息
//  依赖：DailyBreakModel（阶段状态、设置、计时值）
//  被使用：EntryPoint.swift 中通过 MenuBarExtra 加载
//

import SwiftUI

/// 菜单栏弹出面板的主视图，采用卡片式现代设计
///
/// 逻辑：
/// 1. header 根据 phase 显示不同阶段标题和副标题
/// 2. adviceCard 展示健康提示与进度条
/// 3. primaryActions 提供暂停/恢复、立即休息、重置操作
/// 4. footerActions 提供设置与退出按钮
/// 5. overlay 中浮动显示 Toast 消息
struct MenuBarView: View {
    @ObservedObject var model: DailyBreakModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    /// 垂直排列各子视图，整体覆盖毛玻璃 + 渐变背景
    var body: some View {
        VStack(spacing: 10) {
            header
            adviceCard
            primaryActions
            footerActions
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: 320)
        .background(panelBackground)
        .overlay(alignment: .bottom) {
            // 有 toast 消息时在面板底部做一个浮动胶囊浮层
            if let toast = model.toastMessage {
                ToastView(message: toast)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - 子视图

    /// 顶部标题区：阶段标题 + 统计/状态副标题 + 下次休息时间
    private var header: some View {
        VStack(spacing: 4) {
            Text(titleText)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.dailyPrimaryText)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            VStack(spacing: 1) {
                Text(subtitleText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dailySecondaryText)
                    .multilineTextAlignment(.center)

                // 有预设的下次休息时间时，在副标题下方显示
                if let nextBreakLine = model.nextBreakLine {
                    Text(nextBreakLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.dailySecondaryText.opacity(0.85))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 健康建议卡片：图标 Circle + 建议文字 + 进度条，带白色半透明背景和阴影
    private var adviceCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.dailyMint.opacity(0.18))
                Image(systemName: adviceSymbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.dailyMint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 7) {
                Text(adviceText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dailyPrimaryText)
                    .lineLimit(2)

                ProgressBar(value: progressValue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }

    /// 主要操作区：暂停/恢复、立即休息、重置，用 ActionGroup 包裹实现磨砂背景
    private var primaryActions: some View {
        ActionGroup {
            // 暂停状态下显示「恢复」按钮，否则显示「暂停」
            if model.phase == .paused {
                MenuActionRow(title: "恢复", systemImage: "play.fill", tint: .dailyBlue) {
                    performAndClose(model.resume)
                }
            } else {
                MenuActionRow(title: "暂停", systemImage: "pause.fill", tint: .dailyBlue) {
                    performAndClose(model.pause)
                }
            }

            MenuSeparator()

            MenuActionRow(title: "现在休息一下", systemImage: "cup.and.saucer.fill", tint: .dailyMint) {
                performAndClose(model.startBreakNow)
            }

            // 暂停状态下不显示重置，避免干扰
            if model.phase != .paused {
                MenuSeparator()

                MenuActionRow(
                    title: "重新开始本轮",
                    systemImage: "arrow.clockwise",
                    tint: .dailyLavender,
                    isEnabled: model.canResetWorkCycle
                ) {
                    performAndClose(model.resetWorkCycle)
                }
            }
        }
    }

    /// 底部操作区：设置、退出，同样用 ActionGroup 包裹
    private var footerActions: some View {
        ActionGroup {
            MenuActionRow(title: "设置", systemImage: "gearshape.fill", tint: .dailyGray) {
                closeMenuWindow()
                DispatchQueue.main.async {
                    openSettings()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }

            MenuSeparator()

            MenuActionRow(title: "退出 Daily Break", systemImage: "power", tint: .dailyGray) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// 面板背景：ultraThinMaterial + 蓝白渐变 + 白色描边 + 阴影
    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.52),
                                Color.dailyPanelBlue.opacity(0.28),
                                Color.dailyWarmWhite.opacity(0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.13), radius: 18, x: 0, y: 10)
    }

    // MARK: - 计算属性

    /// 根据当前阶段显示不同的标题文案
    ///
    /// 逻辑：
    /// 1. inactive → 礼貌告知今日休息结束
    /// 2. working/preBreak/postponed → 显示剩余工作时间
    /// 3. resting → 显示剩余休息时间
    /// 4. paused/systemAway → 显示已暂停
    private var titleText: String {
        switch model.phase {
        case .inactive:
            return "今天先休息吧"
        case .working, .preBreak, .postponed:
            return "还有 \(formatDuration(model.remainingSeconds)) 可以休息一下"
        case .resting:
            return "正在休息 \(formatDuration(model.remainingSeconds))"
        case .paused:
            return "已暂停"
        case .systemAway:
            return "已暂停"
        }
    }

    /// 副标题：根据不同阶段显示统计数或当前状态说明
    private var subtitleText: String {
        switch model.phase {
        case .inactive:
            return model.statusLine
        case .paused:
            return "已暂停 \(formatDuration(model.remainingSeconds)) · 点击恢复后继续"
        case .systemAway:
            return "锁屏或睡眠期间暂停计时"
        default:
            return "短休息 \(model.todayShortBreaks) 次 · 长休息 \(model.todayLongBreaks) 次"
        }
    }

    /// 根据阶段返回对应的健康建议文案
    private var adviceText: String {
        switch model.phase {
        case .resting(let kind):
            return kind == .short ? "看看远处，放松一下眼睛" : "站起来活动一下，喝口水"
        case .paused, .systemAway:
            return "恢复后会从当前倒计时继续"
        case .inactive:
            return "到设定时间后会自动开始提醒"
        default:
            return "看看远处，放松一下眼睛"
        }
    }

    /// 根据阶段返回对应的 SF Symbol 名称
    private var adviceSymbol: String {
        switch model.phase {
        case .resting(let kind):
            return kind == .short ? "leaf.fill" : "figure.walk"
        case .paused, .systemAway:
            return "pause.fill"
        case .inactive:
            return "sun.min.fill"
        default:
            return "leaf.fill"
        }
    }

    /// 根据阶段计算进度值（休息或工作中的已过时间占比），取值范围 [0, 1]
    private var progressValue: Double {
        switch model.phase {
        case .resting(let kind):
            let total = kind == .short ? model.settings.shortBreakSeconds : model.settings.longBreakSeconds
            return progress(total: total)
        default:
            return progress(total: model.settings.workDurationSeconds)
        }
    }

    // MARK: - 辅助方法

    /// 计算已过时间占总时长的比例
    ///
    /// 逻辑：
    /// 1. elapsed = total - remainingSeconds
    /// 2. 将 elapsed/total 裁剪到 [0, 1]
    private func progress(total: Int) -> Double {
        guard total > 0 else { return 0 }
        let elapsed = max(0, total - model.remainingSeconds)
        return min(1, max(0, Double(elapsed) / Double(total)))
    }

    /// 先关闭菜单面板窗口，再异步执行操作
    ///
    /// 原因：菜单面板关闭后才能呈现模态弹窗（如设置窗口、系统弹窗）
    private func performAndClose(_ action: @escaping () -> Void) {
        closeMenuWindow()
        DispatchQueue.main.async {
            action()
        }
    }

    /// 关闭当前菜单面板窗口
    private func closeMenuWindow() {
        dismiss()
    }
}

// MARK: - 子视图组件

/// 操作按钮组容器：将一组 MenuActionRow 包裹为磨砂背景圆角面板
private struct ActionGroup<Content: View>: View {
    @ViewBuilder var content: Content

    /// 垂直排列内容，叠加白色半透明背景 + 白色描边
    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.5), lineWidth: 1)
        }
    }
}

/// 菜单操作行：图标 Circle + 标题 + 右箭头，支持 hover 高亮和 disabled 状态
private struct MenuActionRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    var isEnabled = true
    let action: () -> Void

    @State private var isHovered = false

    /// 按钮内部使用 HStack 布局，hover 时背景色变为浅绿
    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(isEnabled ? 0.16 : 0.08))
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.42))
                }
                .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dailyPrimaryText.opacity(isEnabled ? 1 : 0.42))

                Spacer()
            }
            .frame(height: 40)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .background(isHovered && isEnabled ? Color.dailyHover : .clear)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }
}

/// 菜单分隔线：左侧缩进 48pt 的细线
private struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.dailySeparator)
            .frame(height: 1)
            .padding(.leading, 48)
    }
}

/// 进度条：Capsule 底色 + 绿色填充，支持动画过渡
private struct ProgressBar: View {
    let value: Double

    /// 利用 GeometryReader 获取可用宽度，按比例绘制绿色填充段
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.dailyTrack)
                Capsule()
                    .fill(Color.dailyMint)
                    .frame(width: proxy.size.width * min(1, max(0, value)))
                    .animation(.easeInOut(duration: 0.25), value: value)
            }
        }
        .frame(height: 5)
    }
}

/// Toast 浮层：胶囊背景显示临时消息，带阴影
private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.dailyPrimaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

// MARK: - 颜色扩展

/// 每日面板统一配色：文字色、品牌色、背景色和辅助色
private extension Color {
    static let dailyPrimaryText = Color(red: 0.14, green: 0.18, blue: 0.25)
    static let dailySecondaryText = Color(red: 0.43, green: 0.49, blue: 0.56)
    static let dailyMint = Color(red: 0.43, green: 0.74, blue: 0.72)
    static let dailyBlue = Color(red: 0.45, green: 0.68, blue: 0.86)
    static let dailyLavender = Color(red: 0.55, green: 0.55, blue: 0.86)
    static let dailyGray = Color(red: 0.58, green: 0.64, blue: 0.67)
    static let dailyTrack = Color(red: 0.83, green: 0.86, blue: 0.88).opacity(0.85)
    static let dailyHover = Color(red: 0.85, green: 0.93, blue: 0.94).opacity(0.55)
    static let dailySeparator = Color(red: 0.72, green: 0.76, blue: 0.78).opacity(0.24)
    static let dailyPanelBlue = Color(red: 0.78, green: 0.91, blue: 0.94)
    static let dailyWarmWhite = Color(red: 0.98, green: 0.94, blue: 0.87)
}
