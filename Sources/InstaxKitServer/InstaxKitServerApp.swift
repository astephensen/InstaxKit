import SwiftUI

@main
struct InstaxKitServerApp: App {
  @StateObject private var viewModel = ServerViewModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(viewModel)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
  }
}
