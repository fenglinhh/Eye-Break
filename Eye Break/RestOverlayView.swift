//
//  RestOverlayView.swift
//  Eye Break
//
//  职责：提供全屏休息蒙层的 SwiftUI 视图，包括主屏幕的详细休息界面和副屏幕的简化提示。
//  依赖：RestOverlayState
//  被使用：RestOverlayController（通过 NSHostingView 嵌入 NSWindow）
//

import Combine
import SwiftUI

/// 全屏蒙层窗口的视图模型
///
/// 逻辑：
/// 1. 持有 @Published state 属性，RestOverlayController 通过更新此属性驱动 UI 刷新
/// 2. isPrimary 区分主屏幕（显示完整内容）和副屏幕（显示简化内容）
/// 3. actionRequested 标记已发起操作，防止跳过操作被重复触发
@MainActor
final class RestOverlayWindowModel: ObservableObject {
    /// 蒙层当前状态，包含倒计时、强度、类型等信息
    @Published var state: RestOverlayState
    /// 是否已发起操作（跳过），用于阻止重复触发
    @Published private(set) var actionRequested = false
    /// 是否为主屏幕，主屏幕显示完整休息界面，副屏幕显示简化版
    let isPrimary: Bool
    /// 跳过休息的闭包，透传给 RestOverlayController.onSkip
    private let onSkip: () -> Void

    init(state: RestOverlayState, isPrimary: Bool, onSkip: @escaping () -> Void) {
        self.state = state
        self.isPrimary = isPrimary
        self.onSkip = onSkip
    }

    /// 发起跳过操作
    ///
    /// 逻辑：
    /// 1. guard 检查 actionRequested，确保跳过操作只执行一次
    /// 2. 立即将 actionRequested 置为 true，禁用跳过按钮
    /// 3. 使用 DispatchQueue.main.async 异步调用 onSkip，避免在视图生命周期中直接触发状态变更
    func skip() {
        guard !actionRequested else { return }
        actionRequested = true
        DispatchQueue.main.async { [onSkip] in
            onSkip()
        }
    }

}

/// 全屏休息界面视图
///
/// 逻辑：
/// 1. 根据 isPrimary 显示不同内容层级：主屏幕展示呼吸动画 + 标题 + 倒计时 + 进度 + 健康建议 + 跳过按钮
/// 2. 副屏幕仅显示提示文字和剩余时间
/// 3. 底层半透明黑色蒙层的透明度由 state.intensity.opacity 控制
struct RestOverlayView: View {
    @ObservedObject var model: RestOverlayWindowModel

    /// 便捷访问 model.state
    private var state: RestOverlayState {
        model.state
    }

    /// 休息进度百分比（0.0 ~ 1.0），用于 ProgressView
    ///
    /// 逻辑：
    /// 1. 防止 totalSeconds 为零导致除零错误
    /// 2. 计算已完成比例: 1 - (剩余秒数 / 总秒数)
    private var progress: Double {
        guard state.totalSeconds > 0 else { return 0 }
        return 1 - (Double(state.remainingSeconds) / Double(state.totalSeconds))
    }

    var body: some View {
        ZStack {
            // 半透明黑色蒙层，覆盖整个屏幕
            Color.black.opacity(state.intensity.opacity)
                .ignoresSafeArea()

            // 主屏幕显示完整休息界面，副屏幕只显示简化状态
            if model.isPrimary {
                primaryContent
            } else {
                secondaryContent
            }
        }
    }

    /// 主屏幕完整休息界面
    ///
    /// 包含：呼吸动画（可选）、休息类型标题、剩余倒计时、进度条、健康建议、跳过按钮
    private var primaryContent: some View {
        VStack(spacing: 22) {
            // 呼吸动画圆，仅在 animationEnabled 时显示
            if state.animationEnabled {
                BreathingCircle()
                    .frame(width: 112, height: 112)
            }

            Text(state.kind == .short ? "短休息时间" : "长休息时间")
                .font(.system(size: 36, weight: .semibold))
            Text(formatDuration(state.remainingSeconds))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 360)
            // 健康建议文本，仅在非空时显示
            if !state.advice.isEmpty {
                Text(state.advice)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("跳过", action: model.skip)
            }
            .controlSize(.large)
            // 跳过按钮在操作已发起时禁用，防止重复触发
            .disabled(model.actionRequested)
        }
        .padding(36)
        .foregroundStyle(.white)
    }

    /// 副屏幕简化休息提示
    ///
    /// 仅显示"当前处于休息状态"和剩余倒计时，不含操作按钮和动画
    private var secondaryContent: some View {
        VStack(spacing: 12) {
            Text("当前处于休息状态")
                .font(.title)
                .fontWeight(.semibold)
            Text("剩余 \(formatDuration(state.remainingSeconds))")
                .font(.largeTitle)
                .monospacedDigit()
        }
        .foregroundStyle(.white)
    }
}

/// 呼吸动画圆形视图
///
/// 逻辑：
/// 1. 初始缩放比例为 0.72，在 onAppear 中触发动画
/// 2. 动画使用 easeInOut 曲线，周期 2.4 秒，自动反转并无限重复
/// 3. 圆形使用半透明青色填充 + 白色边框，营造柔和呼吸感
private struct BreathingCircle: View {
    @State private var scale = 0.72

    var body: some View {
        Circle()
            .fill(.cyan.opacity(0.28))
            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
            .scaleEffect(scale)
            .onAppear {
                // 启动无限循环的缩放动画：从 0.72 到 1.0，模拟呼吸节奏
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    scale = 1
                }
            }
    }
}
