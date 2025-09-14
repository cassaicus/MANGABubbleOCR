import SwiftUI

@main
struct MANGABubbleOCRApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ImageViewerModel.shared) // モデルを注入
        }
    }
}
