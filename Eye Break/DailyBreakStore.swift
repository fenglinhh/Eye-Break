//
//  DailyBreakStore.swift
//  Eye Break
//
//  职责：UserDefaults 持久化层，负责 BreakSettings 和 BreakStats 的读写
//  依赖：BreakModels（BreakSettings、BreakStats）
//  被使用：DailyBreakModel（ViewModel 层）
//

import Foundation

final class DailyBreakStore {
    private enum Key {
        static let settings = "dailyBreak.settings"
        static let stats = "dailyBreak.stats"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// 初始化存储层，可注入自定义 UserDefaults（测试时传入非 standard 实例）
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 从 UserDefaults 读取设置，若不存在则返回默认值
    func loadSettings() -> BreakSettings {
        guard let data = defaults.data(forKey: Key.settings),
              let settings = try? decoder.decode(BreakSettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    /// 将当前设置编码为 JSON 写入 UserDefaults
    func saveSettings(_ settings: BreakSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: Key.settings)
    }

    /// 读取当日统计数据，跨天时自动归零
    ///
    /// 逻辑：
    /// 1. 用 dayKey 比对存储数据的日期和当前日期
    /// 2. 日期不同时返回空白的今日统计数据，实现跨天自动重置
    func loadStats(now: Date = Date(), calendar: Calendar = .current) -> BreakStats {
        let todayKey = BreakStats.dayKey(for: now, calendar: calendar)
        guard let data = defaults.data(forKey: Key.stats),
              let stats = try? decoder.decode(BreakStats.self, from: data),
              stats.dayKey == todayKey else {
            return .today(calendar: calendar, now: now)
        }
        return stats
    }

    /// 将当日统计数据编码为 JSON 写入 UserDefaults
    func saveStats(_ stats: BreakStats) {
        guard let data = try? encoder.encode(stats) else { return }
        defaults.set(data, forKey: Key.stats)
    }
}
