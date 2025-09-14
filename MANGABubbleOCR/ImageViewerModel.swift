import Foundation
import Combine

final class ImageViewerModel: ObservableObject {
    static let shared = ImageViewerModel()

    @Published var currentIndex: Int = 0

    private let _repository: ImageRepository
    var repository: ImageRepository { _repository }

    private init(repository: ImageRepository = ImageRepository()) {
        self._repository = repository

        repository.$images
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.currentIndex >= repository.images.count {
                    self.currentIndex = max(0, repository.images.count - 1)
                }
            }
            .store(in: &cancellables)
    }

    func addImage(url: URL) {
        // 最初の追加時にダミーを削除
        if _repository.images.count == 1 && _repository.images.first?.path == "/dev/null" {
            _repository.images.removeAll()
        }
        _repository.add(url)
    }

    func removeCurrentImage() {
        _repository.remove(at: currentIndex)
        currentIndex = max(0, currentIndex - 1)

        // 全削除されたらダミーを戻す
        if _repository.images.isEmpty {
            _repository.images = [URL(fileURLWithPath: "/dev/null")]
            currentIndex = 0
        }
    }

    func moveImage(from: Int, to: Int) {
        _repository.move(from: from, to: to)
    }

    private var cancellables = Set<AnyCancellable>()
}
