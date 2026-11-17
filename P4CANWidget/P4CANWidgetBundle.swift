import SwiftUI
import WidgetKit

@main
struct P4CANWidgetBundle: WidgetBundle {
    var body: some Widget {
        #if targetEnvironment(macCatalyst)
        CatalystStatusWidget()
        #else
        CanActivityWidget()
        #endif
    }
}
