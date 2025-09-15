import SwiftUI

/// サムネイル画像を非同期に読み込んで表示するビュー。
/// `AsyncFullImageView`と似ているが、サムネイル生成とそれに特化したキャッシュキー管理を行う点が異なる。
struct AsyncImageView: View {
    // 表示する画像の元のURL
    let url: URL
    // 生成するサムネイルの最大サイズ（幅または高さ）
    let maxSize: CGFloat

    // 読み込まれたサムネイル画像を保持するための状態変数
    @State private var image: NSImage?

    /// ビューのイニシャライザ。
    /// - Parameters:
    ///   - url: 表示する画像のURL。
    ///   - maxSize: サムネイルの最大サイズ。デフォルトは200。
    init(url: URL, maxSize: CGFloat = 200) {
        self.url = url
        self.maxSize = maxSize

        // サムネイル用に、元のURLとサイズ情報からユニークなキャッシュキーを生成します。
        // これにより、同じ画像でも異なるサイズのサムネイルを個別にキャッシュできます。
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "thumbnail_size", value: "\(maxSize)")]
        // `thumbKey`は、例えば "file:///path/to/image.jpg?thumbnail_size=200" のようになります。
        let thumbKey = components.url!

        // ビューが再生成された際のちらつきを防ぐため、UI更新前に同期的にキャッシュを確認します。
        // `State(initialValue:)` を使い、`thumbKey`でキャッシュを検索します。
        self._image = State(initialValue: ImageCache.shared.image(for: thumbKey))
    }

    // ビューの本体を定義します。
    var body: some View {
        Group {
            // `image`状態変数がnilでなければ、読み込み済みの画像を表示します。
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // `image`がnilの場合、読み込み中であることを示します。
                // プレースホルダーとして、背景が灰色で中央にインジケーターが表示されます。
                ProgressView()
                    // 親ビューに対して可能な限りの幅と高さを占めるようにします。
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 背景に半透明の灰色を設定し、プレースホルダーの領域を視覚的に示します。
                    .background(Color.gray.opacity(0.1))
                    // このビューが表示されると非同期で`loadImage`メソッドを実行します。
                    .task {
                        await loadImage()
                    }
            }
        }
    }

    /// URLからサムネイル画像を非同期で読み込むプライベートメソッド。
    private func loadImage() async {
        // `ImageCache`シングルトンからサムネイル画像を非同期で取得します。
        // このメソッドは、キャッシュの確認、キャッシュがない場合のサムネイル生成とキャッシュ保存を内部で行います。
        // 取得した画像は`self.image`に設定され、ビューが更新されます。
        self.image = await ImageCache.shared.thumbnail(for: url, maxSize: maxSize)
    }
}
