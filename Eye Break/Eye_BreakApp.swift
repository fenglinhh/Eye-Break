//
//  Eye_BreakApp.swift
//  Eye Break
//
//  职责：应用入口，配置菜单栏图标、弹出窗口和设置面板
//  依赖：DailyBreakModel、MenuBarView、SettingsView
//  被使用：由 @main 自动调用
//

import AppKit
import SwiftUI

@main
struct Eye_BreakApp: App {
    @StateObject private var model = DailyBreakModel()

    var body: some Scene {
        // 菜单栏入口：resting 阶段显示休息图标+倒计时，计数模式仅显示文本，否则显示普通眼睛图标
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Group {
                if case .resting = model.phase {
                    HStack(spacing: 2) {
                        Image(systemName: "figure.mind.and.body")
                            .font(.system(size: 11, weight: .medium))
                        Text(model.menuBarTitle)
                            .monospacedDigit()
                    }
                } else if model.settings.menuBarCountdownEnabled {
                    Text(model.menuBarTitle)
                        .monospacedDigit()
                } else {
                    Image(systemName: "eye")
                }
            }
            .onAppear {
                model.start()
            }
        }
        .menuBarExtraStyle(.window)

        // 设置面板：通过自定义 NSWindow 管理，避免 SwiftUI Settings scene 在 macOS 26 的兼容问题
        // 窗口由 MenuBarView 中的 openSettingsWindow() 手动创建和展示
    }

    /// 将应用设为纯菜单栏模式（无 Dock 图标）
    ///
    /// 逻辑：
    /// 1. .accessory 策略不显示 Dock 图标和切换窗口快捷键
    /// 2. 应用仅在菜单栏拥有入口，符合后台常驻工具类应用的设计
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
