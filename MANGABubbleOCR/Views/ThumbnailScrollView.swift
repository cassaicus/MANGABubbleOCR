import SwiftUI

// サムネイル画像の一覧をグリッド表示し、選択された画像まで自動スクロールする機能を持つビュー
struct ThumbnailScrollView: View {
    // アプリケーションの全体的な状態を管理するImageViewerModelを環境オブジェクトとして受け取る
    // このビュー内でモデルのデータ（例：画像リスト、現在のインデックス）にアクセスするために使用
    @EnvironmentObject var model: ImageViewerModel

    // サムネイル表示と1枚表示を切り替えるための状態（真偽値）へのBinding
    // このビューから親ビュー（ContentView）の状態を変更するために使用
    @Binding var showThumbnails: Bool

    // ビューの本体を定義
    var body: some View {
        // ScrollView内の特定の位置にプログラムでスクロールするための機能を提供
        ScrollViewReader { proxy in
            // 垂直方向にスクロール可能なコンテナビュー
            ScrollView {
                // グリッドレイアウトを効率的に作成するためのコンテナ
                // `columns`パラメータで列のレイアウトを定義し、`spacing`でアイテム間の間隔を指定
                LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    // `model.pages`の各要素に対してループ処理を行い、サムネイル画像を生成
                    // `id: \.self`は、各要素が一意であることをSwiftUIに伝える
                    ForEach(model.pages.indices, id: \.self) { index in
                        // 各サムネイル画像をタップ可能なボタンとして実装
                        Button(action: {
                            // ボタンがタップされた際の処理
                            // 1. モデルの現在のインデックスを、タップされた画像のインデックスに更新
                            model.currentIndex = index
                            // 2. 1枚表示モードに切り替える
                            showThumbnails = false
                        }) {
                            // 非同期で画像を読み込み、表示するためのカスタムビュー
                            // `url`には画像のソースURLを、`maxSize`には表示上の最大サイズを指定
                            AsyncImageView(url: model.pages[index].sourceURL, maxSize: 200)
                                // ビューの高さを固定
                                .frame(height: 200)
                                // フレームからはみ出した部分を切り取る
                                .clipped()
                                // ビューの上に重ねて表示するオーバーレイ
                                .overlay(
                                    // 角丸の四角形を定義
                                    RoundedRectangle(cornerRadius: 4)
                                        // 青色の枠線を追加
                                        .stroke(Color.blue, lineWidth: 4)
                                        // 現在選択中の画像（`index == model.currentIndex`）の場合のみ枠線を表示
                                        .opacity(index == model.currentIndex ? 1 : 0)
                                )
                        }
                        // ボタンのデフォルトのスタイル（例：青色のテキスト）を無効にし、シンプルな外観にする
                        .buttonStyle(PlainButtonStyle())
                        // ScrollViewReaderがこのビューを識別するためのIDを設定
                        .id(index)
                    }
                }
                // グリッド全体の周囲に余白を追加
                .padding()
            }
            // このビュー（ScrollView）が表示されたときに実行される処理
            .onAppear {
                // ScrollViewReaderの`proxy`を使用して、指定したIDを持つビューまでスクロール
                // `model.currentIndex`のIDを持つビュー（つまり、現在選択中のサムネイル）が
                // 画面の中央（`.center`）に表示されるようにスクロールする
                proxy.scrollTo(model.currentIndex, anchor: .center)
            }
        }
    }
}
