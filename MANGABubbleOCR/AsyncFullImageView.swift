import SwiftUI

/// フルサイズの画像を非同期に読み込んで表示するビュー。
struct AsyncFullImageView: View {
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
            }
        }
        .task(id: url) { // urlが変わるたびにタスクを再実行
            // .taskモディファイア内で非同期に画像を読み込む
            await loadImage()
        }
    }

    private func loadImage() async {
        // ImageCacheからフル画像を非同期で取得
        self.image = await ImageCache.shared.fullImage(for: url)
    }
}
