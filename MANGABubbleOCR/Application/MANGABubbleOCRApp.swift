import SwiftUI

// @main属性は、この構造体がアプリケーションのエントリーポイント（開始点）であることを示します。
@main
// Appプロトコルに準拠した、アプリケーションのメイン構造体です。
struct MANGABubbleOCRApp: App {
    // bodyプロパティは、アプリケーションのシーン（ウィンドウ）を定義します。
    var body: some Scene {
        // WindowGroupは、アプリケーションのメインウィンドウを管理するシーンです。
        WindowGroup {
            // アプリケーションのメインビューであるContentViewを生成します。
            ContentView()
                // .environmentObject修飾子を使って、ImageViewerModelの共有インスタンスを
                // ContentViewおよびその全てのサブビューで利用できるようにします（環境オブジェクトとして注入）。
                .environmentObject(ImageViewerModel.shared)
        }
        // ウィンドウのスタイルを、タイトルバーが非表示になるように設定します。
        .windowStyle(.hiddenTitleBar)
    }
}
