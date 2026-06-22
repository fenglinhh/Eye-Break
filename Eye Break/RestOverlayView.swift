import Combine
import SwiftUI

@MainActor
final class RestOverlayWindowModel: ObservableObject {
    @Published var state: RestOverlayState
    @Published private(set) var actionRequested = false
    let isPrimary: Bool
    private let onSkip: () -> Void
    private let onPostpone: () -> Void

    init(state: RestOverlayState, isPrimary: Bool, onSkip: @escaping () -> Void, onPostpone: @escaping () -> Void) {
        self.state = state
        self.isPrimary = isPrimary
        self.onSkip = onSkip
        self.onPostpone = onPostpone
    }

    func skip() {
        guard !actionRequested else { return }
        actionRequested = true
        DispatchQueue.main.async { [onSkip] in
            onSkip()
        }
    }

    func postpone() {
        guard !actionRequested else { return }
        actionRequested = true
        DispatchQueue.main.async { [onPostpone] in
            onPostpone()
        }
    }
}

struct RestOverlayView: View {
    @ObservedObject var model: RestOverlayWindowModel

    private var state: RestOverlayState {
        model.state
    }

    private var progress: Double {
        guard state.totalSeconds > 0 else { return 0 }
        return 1 - (Double(state.remainingSeconds) / Double(state.totalSeconds))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(state.intensity.opacity)
                .ignoresSafeArea()

            if model.isPrimary {
                primaryContent
            } else {
                secondaryContent
            }
        }
    }

    private var primaryContent: some View {
        VStack(spacing: 22) {
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
            if !state.advice.isEmpty {
                Text(state.advice)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("跳过", action: model.skip)
                Button("延后 1 分钟", action: model.postpone)
            }
            .controlSize(.large)
            .disabled(model.actionRequested)
        }
        .padding(36)
        .foregroundStyle(.white)
    }

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

private struct BreathingCircle: View {
    @State private var scale = 0.72

    var body: some View {
        Circle()
            .fill(.cyan.opacity(0.28))
            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    scale = 1
                }
            }
    }
}
