import Foundation
import Combine

final class ImageRepository: ObservableObject {
    @Published var images: [URL] = [
        URL(fileURLWithPath: "/dev/null") // ダミー
    ]

    // MARK: - Public API
    func add(_ url: URL) {
        images.append(url)
    }

    func remove(at index: Int) {
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
    }

    func move(from source: Int, to destination: Int) {
        guard images.indices.contains(source),
              images.indices.contains(destination) else { return }
        let item = images.remove(at: source)
        images.insert(item, at: destination)
    }
}
