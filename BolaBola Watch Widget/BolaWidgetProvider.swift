import WidgetKit
import Foundation

struct BolaWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BolaWidgetEntry {
        BolaWidgetEntry(date: .now, companionValue: 50)
    }

    func getSnapshot(in context: Context, completion: @escaping (BolaWidgetEntry) -> Void) {
        completion(BolaWidgetEntry(date: .now, companionValue: readCompanionValue()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BolaWidgetEntry>) -> Void) {
        let value = readCompanionValue()
        let entry = BolaWidgetEntry(date: .now, companionValue: value)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func readCompanionValue() -> Int {
        let defaults = UserDefaults(suiteName: "group.com.gathxr.BolaBola") ?? .standard
        return defaults.integer(forKey: "bola_companionValue")
    }
}
