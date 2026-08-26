//
//  PreBreakReminderView.swift
//  Eye Break
//
//  职责：提供休息前 30 秒的屏幕右下角轻提示浮层。
//  依赖：AppKit、SwiftUI
//  被使用：DailyBreakModel 通过 PreBreakReminderController 驱动显示/更新/关闭
//

import AppKit
import Combine
import SwiftUI

/// 休息前 30 秒的轻提示窗口模型。
///
/// 逻辑：
/// 1. controller 持有并更新 seconds
/// 2. SwiftUI 视图观察 seconds 实时刷新倒计时
/// 3. 不承载业务状态，只负责浮层展示数据
@MainActor
final class PreBreakReminderWindowModel: ObservableObject {
    @Published var seconds: Int

    init(seconds: Int) {
        self.seconds = seconds
    }
}

/// 休息前 30 秒的屏幕浮层控制器。
///
/// 逻辑：
/// 1. showOrUpdate 在主屏右下角创建一个不抢焦点、忽略鼠标事件的 NSPanel
/// 2. 后续倒计时 tick 只更新 model.seconds，避免每秒强制窗口布局
/// 3. close 立即隐藏窗口并延迟释放 contentView，避免动画残留
@MainActor
final class PreBreakReminderController {
    private let edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 24, right: 18)

    private var window: NSPanel?
    private var model: PreBreakReminderWindowModel?
    private var lastScreenFrame: NSRect?

    func showOrUpdate(seconds: Int) {
        guard (1...30).contains(seconds) else {
            close()
            return
        }

        if let window, let model {
            model.seconds = seconds
            updateFrameIfNeeded(for: window)
            if !window.isVisible {
                window.orderFrontRegardless()
            }
            return
        }

        let model = PreBreakReminderWindowModel(seconds: seconds)
        let panel = NSPanel(
            contentRect: frameForReminder(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: PreBreakReminderView(model: model))
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()

        self.model = model
        self.window = panel
    }

    func close() {
        guard let window else { return }
        self.window = nil
        model = nil
        lastScreenFrame = nil
        window.ignoresMouseEvents = true
        window.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            window.contentView = nil
        }
    }

    private func updateFrameIfNeeded(for window: NSPanel) {
        let screenFrame = currentVisibleFrame()
        guard screenFrame != lastScreenFrame else { return }
        lastScreenFrame = screenFrame
        window.setFrame(frameForReminder(in: screenFrame), display: false)
    }

    private func frameForReminder() -> NSRect {
        let visibleFrame = currentVisibleFrame()
        lastScreenFrame = visibleFrame
        return frameForReminder(in: visibleFrame)
    }

    private func currentVisibleFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func frameForReminder(in visibleFrame: NSRect) -> NSRect {
        return NSRect(
            x: visibleFrame.maxX - PreBreakReminderMetrics.windowSize.width - edgeInsets.right,
            y: visibleFrame.minY + edgeInsets.bottom,
            width: PreBreakReminderMetrics.windowSize.width,
            height: PreBreakReminderMetrics.windowSize.height
        )
    }
}

/// 屏幕右下角的呼吸提示视图。
private struct PreBreakReminderView: View {
    @ObservedObject var model: PreBreakReminderWindowModel

    @State private var isBreathing = false

    var body: some View {
        card
            .frame(width: PreBreakReminderMetrics.cardSize.width, height: PreBreakReminderMetrics.cardSize.height)
            .scaleEffect(isBreathing ? PreBreakReminderMetrics.maxScale : PreBreakReminderMetrics.minScale, anchor: .trailing)
            .opacity(isBreathing ? 1 : 0.86)
            .frame(
                width: PreBreakReminderMetrics.windowSize.width,
                height: PreBreakReminderMetrics.windowSize.height,
                alignment: .trailing
            )
            .background(Color.clear)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.18).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
            .accessibilityLabel("准备休息，\(model.seconds) 秒后开始")
    }

    private var card: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.2))
                Image(systemName: "leaf.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("准备休息")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("\(model.seconds) 秒后开始")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .opacity(0.9)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(reminderBackground)
    }

    private var reminderBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.68, blue: 0.64).opacity(0.96),
                        Color(red: 0.16, green: 0.55, blue: 0.76).opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.34), lineWidth: 1)
            }
            .shadow(
                color: Color(red: 0.20, green: 0.68, blue: 0.64).opacity(isBreathing ? 0.42 : 0.18),
                radius: isBreathing ? 18 : 8,
                x: 0,
                y: 6
            )
    }
}

private enum PreBreakReminderMetrics {
    static let cardSize = NSSize(width: 244, height: 76)
    static let minScale = 0.98
    static let maxScale = 1.045

    /// 窗口是透明画布，尺寸按最大缩放计算，避免呼吸动画被窗口边界裁切。
    static var windowSize: NSSize {
        NSSize(
            width: ceil(cardSize.width * maxScale),
            height: ceil(cardSize.height * maxScale)
        )
    }
}
