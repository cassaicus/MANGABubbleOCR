import SwiftUI

@main
struct MANGABubbleOCRApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ImageViewerModel.shared)
        }
        .windowStyle(.hiddenTitleBar)   // ← タイトルバーを非表示
    }
}
