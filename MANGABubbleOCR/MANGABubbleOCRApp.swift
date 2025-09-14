import SwiftUI

@main
struct MANGABubbleOCRApp: App {
    // 共有シングルトンを作成してアプリ全体で使う
    @StateObject private var viewerModel = ImageViewerModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewerModel)   // 子ビューで @EnvironmentObject が取得できる
        }
        .windowStyle(HiddenTitleBarWindowStyle())   // macOS らしいウィンドウにしたいとき
    }
}
