import SwiftUI

@main
struct SubMaxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1180, minHeight: 760)
                .task {
                    await store.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
