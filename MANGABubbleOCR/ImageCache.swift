import SwiftUI

/// 画像データをメモリ内にキャッシュするためのシングルトンクラス。
///
/// このクラスは`NSCache`を利用して、画像データを効率的にキャッシュします。
/// `NSCache`はスレッドセーフであり、メモリが逼迫した際には自動的にキャッシュを破棄するため、
/// アプリケーションのパフォーマンスと安定性に貢献します。
final class ImageCache {
    /// アプリケーション全体で共有される唯一のインスタンス。
    static let shared = ImageCache()

    /// 画像のURL（NSURL）をキー、NSImageを値として保持するキャッシュ。
    /// NSCacheはスレッドセーフであり、メモリが逼迫した際には自動的にオブジェクトを破棄します。
    private let cache = NSCache<NSURL, NSImage>()

    /// シングルトンパターンを強制するため、`init`をプライベートに宣言します。
    private init() {
        // キャッシュに保持するオブジェクト数の上限を設定します。これにより、メモリ使用量が過度に増加するのを防ぎます。
        cache.countLimit = 100
    }

    /// 指定されたURLに対応する画像をキャッシュから取得します。
    /// NSCacheはスレッドセーフなため、同期処理は不要です。
    /// - Parameter url: 取得したい画像のURL。
    /// - Returns: キャッシュに存在すれば`NSImage`、なければ`nil`。
    func image(for url: URL) -> NSImage? {
        return cache.object(forKey: url as NSURL)
    }

    /// 指定されたURLに画像をセット（または更新）します。
    /// NSCacheはスレッドセーフなため、同期処理は不要です。
    /// - Parameters:
    ///   - image: キャッシュする`NSImage`。
    ///   - url: 画像に対応するURL。
    func setImage(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

extension ImageCache {
    /// 内部で利用する、URLから画像データを非同期に読み込むヘルパー関数。
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
    ///
    /// サムネイルはフルサイズの画像とは別のキーでキャッシュされます。
    /// - Parameters:
    ///   - url: サムネイルを取得したい画像のURL。
    ///   - maxSize: サムネイルの最大サイズ（幅または高さ）。
    /// - Returns: 生成または取得したサムネイル画像。処理に失敗した場合は`nil`。
    func thumbnail(for url: URL, maxSize: CGFloat = 200) async -> NSImage? {
        // サムネイル用にユニークなキャッシュキーを生成
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "thumbnail_size", value: "\(maxSize)")]
        let thumbKey = components.url!

        if let cachedImage = image(for: thumbKey) {
            return cachedImage
        }

        guard let data = await loadImageData(from: url), let image = NSImage(data: data) else {
            return nil
        }

        let thumbnail = image.resized(toMax: maxSize)
        setImage(thumbnail, for: thumbKey)
        return thumbnail
    }

    /// 指定されたURLのフルサイズの画像を非同期で取得またはキャッシュから取得します。
    ///
    /// - Parameter url: 画像を取得したいURL。
    /// - Returns: 取得したフルサイズの画像。処理に失敗した場合は`nil`。
    func fullImage(for url: URL) async -> NSImage? {
        if let cachedImage = image(for: url) {
            return cachedImage
        }

        guard let data = await loadImageData(from: url), let image = NSImage(data: data) else {
            return nil
        }

        setImage(image, for: url)
        return image
    }
}

extension NSImage {
    /// アスペクト比を維持したまま、指定された最大サイズに収まるように画像をリサイズします。
    /// - Parameter maxSize: リサイズ後の画像の幅または高さの最大値。
    /// - Returns: リサイズされた新しい`NSImage`インスタンス。
    func resized(toMax maxSize: CGFloat) -> NSImage {
        // 元の画像の幅と高さのうち、大きい方が`maxSize`になるように縮小率を計算します。
        let ratio = min(maxSize / size.width, maxSize / size.height)
        // 新しいサイズを計算します。
        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)

        // 新しいサイズの空の`NSImage`を作成します。
        let newImage = NSImage(size: newSize)
        // `lockFocus`を呼び出して、描画コンテキストをこの新しい画像に設定します。
        newImage.lockFocus()
        // 元の画像を、計算された新しいサイズで描画します。
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        // 描画コンテキストを解放します。
        newImage.unlockFocus()
        return newImage
    }
}
