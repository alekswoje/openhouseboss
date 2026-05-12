import SwiftUI
import WidgetKit

// Entry point for the OpenHouseBossWidgets extension. WidgetKit looks for
// the @main WidgetBundle on launch and registers everything in `body`.
// Right now we only ship the recording Live Activity; if home-screen
// widgets get added later they slot in here next to it.
@main
struct OpenHouseBossWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
    }
}
