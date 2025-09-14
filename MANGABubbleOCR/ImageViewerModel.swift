import SwiftUI

class ImageViewerModel: ObservableObject {
    static let shared = ImageViewerModel()
    
    @Published var images: [URL] = []
    @Published var currentIndex: Int = 0
    
    var currentImage: NSImage? {
        guard currentIndex >= 0, currentIndex < images.count else { return nil }
        return NSImage(contentsOf: images[currentIndex])
    }
    
    private init() {}
    
    func setImages(_ urls: [URL]) {
        self.images = urls
        self.currentIndex = 0
    }
}
