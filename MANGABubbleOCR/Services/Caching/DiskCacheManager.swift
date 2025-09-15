import Foundation
import CryptoKit

/// ディスクキャッシュへのアクセスを管理するコンポーネント。
struct DiskCacheManager {
    /// キャッシュを保存するディレクトリのURL。
    private let cacheDirectory: URL
    private let fileManager = FileManager.default

    /// 初期化時にキャッシュディレクトリのセットアップを試みます。
    init?() {
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        // アプリケーション固有のキャッシュディレクトリパスを作成
        // 通常はここにバンドルIDなどを使うと良い
        let directory = appSupportURL.appendingPathComponent("MANGABubbleOCR/ImageCache")
        self.cacheDirectory = directory

        // ディレクトリが存在しない場合は作成
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// 指定されたキー（URL）に対応するキャッシュファイルのパスを生成します。
    /// - Parameter key: キャッシュのキーとなるURL。
    /// - Returns: ディスク上のキャッシュファイルの完全なURL。
    private func path(for key: URL) -> URL {
        // URLの絶対文字列からSHA256ハッシュを計算し、ファイル名とする
        let digest = SHA256.hash(data: Data(key.absoluteString.utf8))
        let fileName = digest.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(fileName)
    }

    /// 指定されたキーでデータをディスクに保存します。
    /// - Parameters:
    ///   - data: 保存するデータ。
    ///   - key: キャッシュのキーとなるURL。
    func setData(_ data: Data, for key: URL) {
        let filePath = path(for: key)
        try? data.write(to: filePath)
    }

    /// 指定されたキーでディスクからデータを取得します。
    /// - Parameter key: キャッシュのキーとなるURL。
    /// - Returns: 取得したデータ。キャッシュが存在しない場合は`nil`。
    func data(for key: URL) -> Data? {
        let filePath = path(for: key)
        return try? Data(contentsOf: filePath)
    }
}
