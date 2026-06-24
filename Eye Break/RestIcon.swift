//
//  RestIcon.swift
//  Eye Break
//
//  职责：从 App Bundle 加载 rest-icon.svg 并显示为菜单栏模板图标
//  依赖：rest-icon.svg（放置在 app bundle 中的资源文件）
//  被使用：MenuBarExtra 的 label 中在 resting 阶段显示
//

import SwiftUI
import AppKit

struct RestIcon: View {
    var body: some View {
        if let icon = restIconImage {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    /// 从 Bundle 加载 SVG 图标，设置为模板图片以适配菜单栏明暗主题
    ///
    /// 逻辑：
    /// 1. 通过 Bundle.main.url 定位 rest-icon.svg 的资源路径
    /// 2. NSImage(contentsOf:) 加载图片，isTemplate = true 使其跟随系统色调
    /// 3. 若资源缺失或加载失败，静默返回 nil
    private var restIconImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "rest-icon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}
