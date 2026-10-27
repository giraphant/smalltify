import SwiftUI

struct SettingsWindow: View {
    let model: SmalltifyModel
    @State private var tab = "connection"

    var body: some View {
        TabView(selection: $tab) {
            Tab("连接", systemImage: "link", value: "connection") {
                ConnectionSettings(model: model)
            }
            Tab("关于", systemImage: "info.circle", value: "about") {
                AboutSettings()
            }
        }
        .frame(width: 720, height: 640)
        .onAppear {
            #if DEBUG
                if DebugFixtures.opens("about") { tab = "about" }
            #endif
        }
    }
}
