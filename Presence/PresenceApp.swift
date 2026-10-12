import SwiftUI

@main
struct PresenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Presence", id: "panel") {
            PanelView(model: model, showsWordmark: false, clearsWindow: true)
                .onAppear { model.start() }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)

        MenuBarExtra {
            PanelView(model: model, showsWordmark: true, clearsWindow: false)
                .onAppear { model.start() }
        } label: {
            Image(nsImage: MenuMark.image(recording: model.isRecording, away: model.isAway))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
