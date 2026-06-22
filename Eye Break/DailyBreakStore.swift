import Foundation

final class DailyBreakStore {
    private enum Key {
        static let settings = "dailyBreak.settings"
        static let stats = "dailyBreak.stats"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSettings() -> BreakSettings {
        guard let data = defaults.data(forKey: Key.settings),
              let settings = try? decoder.decode(BreakSettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    func saveSettings(_ settings: BreakSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: Key.settings)
    }

    func loadStats(now: Date = Date(), calendar: Calendar = .current) -> BreakStats {
        let todayKey = BreakStats.dayKey(for: now, calendar: calendar)
        guard let data = defaults.data(forKey: Key.stats),
              let stats = try? decoder.decode(BreakStats.self, from: data),
              stats.dayKey == todayKey else {
            return .today(calendar: calendar, now: now)
        }
        return stats
    }

    func saveStats(_ stats: BreakStats) {
        guard let data = try? encoder.encode(stats) else { return }
        defaults.set(data, forKey: Key.stats)
    }
}
