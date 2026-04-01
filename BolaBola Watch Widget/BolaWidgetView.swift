import SwiftUI
import WidgetKit

struct BolaWidgetView: View {
    var entry: BolaWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(entry.imageName)
                    .resizable()
                    .scaledToFit()
                    .widgetAccentable()
            }
        case .accessoryCorner:
            ZStack {
                AccessoryWidgetBackground()
                Image(entry.imageName)
                    .resizable()
                    .scaledToFit()
                    .widgetAccentable()
            }
            .widgetLabel {
                Gauge(value: Double(entry.companionValue), in: 0...100) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(entry.companionValue)")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("100")
                }
            }
        default:
            EmptyView()
        }
    }
}
