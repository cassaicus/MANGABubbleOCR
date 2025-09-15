import SwiftUI

struct AsyncImageView: View {
    let url: URL
    let maxSize: CGFloat

    @State private var image: NSImage?

    init(url: URL, maxSize: CGFloat = 200) {
        self.url = url
        self.maxSize = maxSize

        // サムネイル用にユニークなキャッシュキーを生成
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "thumbnail_size", value: "\(maxSize)")]
        let thumbKey = components.url!

        // ビューが再生成された際のちらつきを防ぐため、同期的にキャッシュを確認
        self._image = State(initialValue: ImageCache.shared.image(for: thumbKey))
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .task {
                        await loadImage()
                    }
            }
        }
    }

    private func loadImage() async {
        self.image = await ImageCache.shared.thumbnail(for: url, maxSize: maxSize)
    }
}
