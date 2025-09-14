import Foundation

class ImageRepository {
    static let shared = ImageRepository()
    
    private init() {}
    
    func fetchLocalImages(from folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        return items.filter { $0.pathExtension.lowercased() == "jpg" }
    }
}
