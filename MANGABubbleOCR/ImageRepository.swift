import Foundation
import AppKit
import ImageIO
import Combine

/// 画像のメタデータを表現する構造体。
///
/// ファイルシステムから取得した画像の基本的な情報を保持します。
struct ImageItem {
    /// 画像ファイルの場所を示すURL。
    let url: URL
    /// ファイル名。
    let name: String
    /// ファイルサイズ（バイト単位）。
    let fileSize: Int64?
    /// ファイルの作成日。
    let creationDate: Date?
}

/// 画像ファイルの入出力（IO）を担当するシングルトンクラス。
///
/// ファイルシステムから画像を読み込む機能や、指定されたディレクトリの変更を監視する機能を提供します。
final class ImageRepository {
    /// アプリケーション全体で共有される唯一のインスタンス。
    static let shared = ImageRepository()
    
    /// 読み込みを許可する画像の拡張子セット。小文字で指定します。
    var allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]
    
    /// ディレクトリ変更を監視するためのDispatchSource。
    private var dirMonitorSource: DispatchSourceFileSystemObject?
    /// 監視対象ディレクトリのファイルディスクリプタ。
    private var monitoredFD: Int32 = -1
    
    /// シングルトンパターンを強制するため、`init`をプライベートに宣言します。
    private init() {}
    
    // MARK: - Image Fetching

    /// 指定されたフォルダから画像ファイルのURLを同期的に取得します（非再帰）。
    /// - Parameter folder: 画像を検索するフォルダのURL。
    /// - Returns: 見つかった画像ファイルのURLの配列。ファイル名でソートされています。
    func fetchLocalImages(from folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        return items
            .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    
    /// 指定されたフォルダから画像ファイルのURLを非同期的に取得します（完了コールバック形式）。
    /// - Parameters:
    ///   - folder: 画像を検索するフォルダのURL。
    ///   - recursive: サブフォルダも再帰的に検索するかどうか。
    ///   - completion: 取得完了時に呼び出されるコールバック。見つかったURLの配列を引数に取ります。
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
    
    /// 指定されたフォルダから画像ファイルのURLを非同期的に取得します（Swift Concurrency版）。
    /// - Parameters:
    ///   - folder: 画像を検索するフォルダのURL。
    ///   - recursive: サブフォルダも再帰的に検索するかどうか。
    /// - Returns: 見つかった画像ファイルのURLの配列。ファイル名でソートされています。
    @available(macOS 12.0, *)
    func fetchLocalImagesAsync(from folder: URL, recursive: Bool = false) async -> [URL] {
        await withCheckedContinuation { cont in
            fetchLocalImagesAsync(from: folder, recursive: recursive) { urls in
                cont.resume(returning: urls)
            }
        }
    }
    
    /// 指定されたフォルダから画像のメタデータ(`ImageItem`)のリストを取得します。
    /// - Parameter folder: 画像を検索するフォルダのURL。
    /// - Returns: 見つかった画像の`ImageItem`の配列。
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
    
    // MARK: - Directory Monitoring

    /// 指定されたフォルダの変更監視を開始します。
    ///
    /// フォルダ内でファイルの書き込み（作成、変更、削除）が検知されると、指定されたコールバックが実行されます。
    /// - Parameters:
    ///   - folder: 監視するフォルダのURL。
    ///   - callback: 変更が検知されたときに実行されるコールバック。UIの更新はメインスレッドで行う必要があります。
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
    
    /// ディレクトリの変更監視を停止します。
    func stopMonitoring() {
        dirMonitorSource?.cancel()
    }
}
