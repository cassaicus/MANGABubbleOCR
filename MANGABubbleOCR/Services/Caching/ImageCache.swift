import SwiftUI

/// 画像データをメモリ内およびディスク上にキャッシュするためのシングルトンクラス。
///
/// メモリキャッシュ（NSCache）とディスクキャッシュ（DiskCacheManager）の2段階キャッシュを提供します。
/// 1. まずメモリキャッシュを検索します（最速）。
/// 2. メモリになければディスクキャッシュを検索します（高速）。
/// 3. どちらにもなければ、ネットワークまたはファイルシステムからデータを読み込み、両方のキャッシュに保存します。
final class ImageCache {
    /// アプリケーション全体で共有される唯一のインスタンス。
    static let shared = ImageCache()

    /// 画像のURL（NSURL）をキー、NSImageを値として保持するメモリキャッシュ。
    private let memoryCache = NSCache<NSURL, NSImage>()
    /// ディスクキャッシュを管理するコンポーネント。
    private let diskCache: DiskCacheManager?

    /// シングルトンパターンを強制するため、`init`をプライベートに宣言します。
    private init() {
        self.diskCache = DiskCacheManager()
        // メモリキャッシュに保持するオブジェクト数の上限を設定します。
        memoryCache.countLimit = 100
    }

    /// 指定されたURLに対応する画像をメモリキャッシュから取得します。
    /// - Parameter url: 取得したい画像のURL。
    /// - Returns: キャッシュに存在すれば`NSImage`、なければ`nil`。
    func image(for url: URL) -> NSImage? {
        return memoryCache.object(forKey: url as NSURL)
    }

    /// 指定されたURLに画像をメモリキャッシュにセットします。
    /// - Parameters:
    ///   - image: キャッシュする`NSImage`。
    ///   - url: 画像に対応するURL。
    func setImage(_ image: NSImage, for url: URL) {
        memoryCache.setObject(image, forKey: url as NSURL)
    }
}

extension ImageCache {
    /// URLから画像データを非同期に読み込みます。（ネットワークまたはローカルファイル）
    private func loadImageData(from url: URL) async -> Data? {
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } catch {
            print("画像のダウンロードに失敗しました: \(url) - \(error)")
            return nil
        }
    }

    /// 指定されたURLのサムネイルを非同期で生成またはキャッシュから取得します。
    func thumbnail(for url: URL, maxSize: CGFloat = 200) async -> NSImage? {
        // サムネイル用にユニークなキャッシュキーを生成
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "thumbnail_size", value: "\(maxSize)")]
        let thumbKey = components.url!

        // 1. メモリキャッシュを確認
        if let cachedImage = image(for: thumbKey) {
            return cachedImage
        }

        // 2. ディスクキャッシュを確認
        if let data = diskCache?.data(for: thumbKey), let image = NSImage(data: data) {
            setImage(image, for: thumbKey) // メモリキャッシュにも保存
            return image
        }

        // 3. ネットワーク/ファイルから読み込み
        guard let data = await loadImageData(from: url), let image = NSImage(data: data) else {
            return nil
        }

        let thumbnail = image.resized(toMax: maxSize)
        // ディスクとメモリの両方にキャッシュ
        diskCache?.setData(thumbnail.tiffRepresentation!, for: thumbKey)
        setImage(thumbnail, for: thumbKey)
        return thumbnail
    }

    /// 指定されたURLのフルサイズの画像を非同期で取得またはキャッシュから取得します。
    func fullImage(for url: URL) async -> NSImage? {
        // 1. メモリキャッシュを確認
        if let cachedImage = image(for: url) {
            return cachedImage
        }

        // 2. ディスクキャッシュを確認
        if let data = diskCache?.data(for: url), let image = NSImage(data: data) {
            setImage(image, for: url) // メモリキャッシュにも保存
            return image
        }

        // 3. ネットワーク/ファイルから読み込み
        guard let data = await loadImageData(from: url), let image = NSImage(data: data) else {
            return nil
        }

        // ディスクとメモリの両方にキャッシュ
        diskCache?.setData(data, for: url)
        setImage(image, for: url)
        return image
    }
}

extension NSImage {
    /// アスペクト比を維持したまま、指定された最大サイズに収まるように画像をリサイズします。
    func resized(toMax maxSize: CGFloat) -> NSImage {
        let ratio = min(maxSize / size.width, maxSize / size.height)
        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
