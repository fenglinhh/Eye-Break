//
//  Eye_BreakApp.swift
//  Eye Break
//
//  Created by Flynn on 22/6/26.
//

import AppKit
import SwiftUI

@main
struct Eye_BreakApp: App {
    @StateObject private var model = DailyBreakModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .onAppear {
                    model.start()
                }
        } label: {
            Group {
                if model.settings.menuBarCountdownEnabled {
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

        Settings {
            SettingsView(model: model)
                .onAppear {
                    model.start()
                }
        }
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
