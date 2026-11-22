import SwiftUI

@main
struct GoutoujunshiApp: App {
    @StateObject private var store = ChatStore()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(store)
        }
    }
}
