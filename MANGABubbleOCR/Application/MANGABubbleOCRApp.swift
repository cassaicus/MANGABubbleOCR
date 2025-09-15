import SwiftUI

// @main属性は、この構造体がアプリケーションのエントリーポイント（開始点）であることを示します。
@main
// Appプロトコルに準拠した、アプリケーションのメイン構造体です。
struct MANGABubbleOCRApp: App {
    //【将来的な改善提案】
    // 現在はシングルトンパターンでViewModelや各種サービスにアクセスしています。
    // アプリケーションがさらに複雑化し、テストの必要性が高まった場合には、
    // DI (Dependency Injection) コンテナを導入することを推奨します。
    //
    // DIコンテナ（例: Swinject, Factoryなど）を利用することで、
    // ・各コンポーネントの依存関係が明確になる
    // ・単体テスト時にモックオブジェクトへの差し替えが容易になる
    // ・ビューとロジックの結合度が下がり、より疎結合な設計になる
    // といったメリットがあります。
    //
    // その場合、以下のようにDIコンテナで生成したインスタンスを
    // @StateObjectとしてビューに渡す形になります。
    //
    //例:
    // @StateObject private var model = DIContainer.shared.resolve(ImageViewerModel.self)

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
