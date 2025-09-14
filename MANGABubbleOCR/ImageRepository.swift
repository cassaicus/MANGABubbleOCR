import Foundation
import AppKit
import ImageIO
import Combine

struct ImageItem {
    let url: URL
    let name: String
    let fileSize: Int64?
    let creationDate: Date?
}

final class ImageRepository {
    static let shared = ImageRepository()
    
    // 拡張子リスト（必要なら追加）
    var allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]
    
    // サムネイルキャッシュ
    private let thumbCache = NSCache<NSURL, NSImage>()
    
    // 監視用ハンドル
    private var dirMonitorSource: DispatchSourceFileSystemObject?
    private var monitoredFD: Int32 = -1
    
    private init() {}
    
    // MARK: - 簡易同期取得（既存互換）
    func fetchLocalImages(from folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        return items
            .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    
    // MARK: - 非同期（completion）
    func fetchLocalImagesAsync(from folder: URL, recursive: Bool = false, completion: @escaping ([URL]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { completion([]); return }
            var results: [URL] = []
            if recursive {
                let fm = FileManager.default
                let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let file = enumerator?.nextObject() as? URL {
                    if self.allowedExtensions.contains(file.pathExtension.lowercased()) {
                        results.append(file)
                    }
                }
            } else {
                results = self.fetchLocalImages(from: folder)
            }
            results.sort { $0.lastPathComponent < $1.lastPathComponent }
            completion(results)
        }
    }
    
    // MARK: - Swift concurrency 版（macOS 12+）
    @available(macOS 12.0, *)
    func fetchLocalImagesAsync(from folder: URL, recursive: Bool = false) async -> [URL] {
        await withCheckedContinuation { cont in
            fetchLocalImagesAsync(from: folder, recursive: recursive) { urls in
                cont.resume(returning: urls)
            }
        }
    }
    
    // MARK: - メタデータ付き取得
    func fetchImageItems(from folder: URL) -> [ImageItem] {
        let urls = fetchLocalImages(from: folder)
        let fm = FileManager.default
        return urls.map { url in
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value
            let cdate = attrs?[.creationDate] as? Date
            return ImageItem(url: url, name: url.lastPathComponent, fileSize: size, creationDate: cdate)
        }
    }
    
    // MARK: - サムネイル生成（キャッシュする）
    func thumbnail(for url: URL, maxPixelSize: Int = 400) -> NSImage? {
        if let cached = thumbCache.object(forKey: url as NSURL) { return cached }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [NSString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        let ns = NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
        thumbCache.setObject(ns, forKey: url as NSURL)
        return ns
    }
    
    // MARK: - ディレクトリ監視（簡易）
    func startMonitoring(folder: URL, callback: @escaping () -> Void) {
        stopMonitoring()
        monitoredFD = open(folder.path, O_EVTONLY)
        guard monitoredFD >= 0 else { return }
        dirMonitorSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: monitoredFD, eventMask: .write, queue: DispatchQueue.global())
        dirMonitorSource?.setEventHandler(handler: {
            // 変更を検知 → コールバック（呼び出し側はメインスレッドで処理すること）
            callback()
        })
        dirMonitorSource?.setCancelHandler {
            close(self.monitoredFD)
            self.monitoredFD = -1
            self.dirMonitorSource = nil
        }
        dirMonitorSource?.resume()
    }
    
    func stopMonitoring() {
        dirMonitorSource?.cancel()
    }
}
