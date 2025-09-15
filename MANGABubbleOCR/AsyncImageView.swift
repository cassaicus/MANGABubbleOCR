import SwiftUI

struct AsyncImageView: View {
    let url: URL

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // 画像読み込み中はインジケーターを表示
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
            }
        }
        .task {
            // .taskモディファイア内で非同期に画像を読み込む
            await loadImage()
        }
    }

    private func loadImage() async {
        // すでに画像があれば何もしない
        guard image == nil else { return }

        // ImageCacheからサムネイルを非同期で取得
        self.image = await ImageCache.shared.thumbnail(for: url)
    }
}
