import SwiftUI

/// フルサイズの画像を非同期に読み込んで表示するビュー。
/// 画像の読み込み中はプログレスインジケーターを表示し、読み込み完了後に画像を表示します。
/// 画像のキャッシュ（ImageCache）を利用して、一度読み込んだ画像の再表示を高速化します。
struct AsyncFullImageView: View {
    // 表示する画像のURL
    let url: URL

    // 読み込まれた画像を保持するための状態変数。`NSImage`はmacOSの画像オブジェクト。
    // `@State`プロパティラッパーにより、この値が変更されるとビューが再描画される。
    @State private var image: NSImage?

    /// ビューのイニシャライザ。
    /// - Parameter url: 表示する画像のURL。
    init(url: URL) {
        self.url = url
        // ビューが再生成された際のちらつきを防ぐため、UIの更新前に同期的にキャッシュを確認します。
        // `State(initialValue:)` を使うことで、`init`内で`@State`プロパティを初期化しています。
        // これにより、ビューが表示される前にキャッシュ画像があれば即座に表示できます。
        self._image = State(initialValue: ImageCache.shared.image(for: url))
    }

    // ビューの本体を定義します。
    var body: some View {
        // `Group`は複数のビューをまとめるためのコンテナで、この場合は条件分岐のために使用されています。
        Group {
            // `image`状態変数がnilでない場合（つまり、画像が読み込み済みの場合）
            if let image = image {
                // `NSImage`をSwiftUIの`Image`に変換して表示します。
                Image(nsImage: image)
                    // 画像をリサイズ可能にします。
                    .resizable()
                    // アスペクト比を維持したまま、親ビューのサイズに合わせて表示モードを設定します（.fitは全体が収まるように調整）。
                    .aspectRatio(contentMode: .fit)
            } else {
                // `image`がnilの場合（つまり、まだ読み込みが完了していない、または失敗した場合）
                // 読み込み中であることを示す円形のプログレスインジケーターを表示します。
                ProgressView()
                    // このビューが表示されると非同期タスクを開始する`.task`モディファイア。
                    // `await`キーワードで非同期処理の完了を待ちます。
                    .task {
                        await loadImage()
                    }
            }
        }
    }

    /// URLから画像を非同期で読み込むプライベートメソッド。
    private func loadImage() async {
        // `ImageCache`シングルトンからフルサイズの画像を非同期で取得します。
        // このメソッドはキャッシュの確認と、キャッシュがない場合のネットワークやファイルからの読み込みを内部で処理します。
        // 取得した画像は`self.image`状態変数に設定され、ビューの再描画がトリガーされます。
        self.image = await ImageCache.shared.fullImage(for: url)
    }
}
