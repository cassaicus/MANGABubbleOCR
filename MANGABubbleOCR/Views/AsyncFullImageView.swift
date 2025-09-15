import SwiftUI

/// フルサイズの画像を非同期に読み込んで表示するビュー。
struct AsyncFullImageView: View {
    let url: URL

    @State private var image: NSImage?

    init(url: URL) {
        self.url = url
        // ビューが再生成された際のちらつきを防ぐため、同期的にキャッシュを確認
        self._image = State(initialValue: ImageCache.shared.image(for: url))
    }

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // キャッシュにない場合のみ、非同期読み込みを実行
                ProgressView()
                    .task {
                        await loadImage()
                    }
            }
        }
    }

    private func loadImage() async {
        // ImageCacheからフル画像を非同期で取得
        self.image = await ImageCache.shared.fullImage(for: url)
    }
}
