import SwiftUI

class ImageViewerModel: ObservableObject {
    static let shared = ImageViewerModel()
    
    @Published var images: [URL] = []
    @Published var currentIndex: Int = 0
    
    // 現在の画像
    var currentImage: NSImage? {
        guard currentIndex >= 0, currentIndex < images.count else { return nil }
        return NSImage(contentsOf: images[currentIndex])
    }
    
    private init() {}
    
    // テスト用のjpg読み込み
    func loadSampleImage() {
        if let url = Bundle.main.url(forResource: "sample", withExtension: "jpg") {
            images = [url]
            currentIndex = 0
        }
    }
}
