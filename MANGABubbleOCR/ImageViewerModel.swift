import SwiftUI

// このクラスは、UIの状態管理と更新を担当します。
// 表示する画像のリストや、現在表示中の画像のインデックスなどを管理し、
// SwiftUIビューにUIの変更を通知します。
class ImageViewerModel: ObservableObject {
    // ImageViewerModelの唯一のインスタンスを生成し、どこからでもアクセスできるようにします（シングルトンパターン）。
    static let shared = ImageViewerModel()
    
    // 表示する画像のURLの配列。@Publishedプロパティラッパーにより、この値が変更されるとUIが自動的に更新されます。
    @Published var images: [URL] = []
    // 現在表示している画像のインデックス。@Publishedプロパティラッパーにより、この値が変更されるとUIが自動的に更新されます。
    @Published var currentIndex: Int = 0
    
    // 現在表示している画像（NSImage）を返すコンピューテッドプロパティ。
    var currentImage: NSImage? {
        // 現在のインデックスが画像の範囲内にあるかを確認します。
        guard currentIndex >= 0, currentIndex < images.count else { return nil }
        // インデックスに対応するURLからNSImageを生成して返します。
        return NSImage(contentsOf: images[currentIndex])
    }
    
    // 外部からのインスタンス化を防ぐために、initをprivateに設定します。
    private init() {}
    
    // 表示する画像のリストをセットアップします。
    func setImages(_ urls: [URL]) {
        // 新しい画像のURL配列を設定します。
        self.images = urls
        // 現在のインデックスを先頭（0）にリセットします。
        self.currentIndex = 0
    }
    
    func loadFolder(_ folder: URL) {
        ImageRepository.shared.fetchLocalImagesAsync(from: folder) { [weak self] urls in
            DispatchQueue.main.async {
                self?.images = urls
                self?.currentIndex = 0
            }
        }
    }
    // サムネを表示したいとき
    func thumbnail(for url: URL) -> NSImage? {
        ImageRepository.shared.thumbnail(for: url, maxPixelSize: 200)
    }
}
