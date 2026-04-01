import WidgetKit
import SwiftUI

struct BolaWidget: Widget {
    let kind = "BolaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BolaWidgetProvider()) { entry in
            BolaWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Bola")
        .description("Shows Bola's mood and companion value.")
        .supportedFamilies([.accessoryCorner, .accessoryCircular])
    }
}

@main
struct BolaWidgetBundle: WidgetBundle {
    var body: some Widget {
        BolaWidget()
    }
}
