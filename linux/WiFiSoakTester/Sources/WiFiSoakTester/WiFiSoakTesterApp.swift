import SwiftUI

@main
struct WiFiSoakTesterApp: App {
    @StateObject private var viewModel = SoakTestViewModel()

    var body: some Scene {
        WindowGroup("Wi-Fi Soak Tester", id: "main") {
            MainView(viewModel: viewModel)
                .frame(minWidth: 1200, minHeight: 760)
        }

        MenuBarExtra(viewModel.menuBarTitle, systemImage: viewModel.isRunning ? "speedometer" : "wifi") {
            MenuBarStatusView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
