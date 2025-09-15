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
    /// 指定されたURLのサムネイルを非同期で生成またはキャッシュから取得します。
    ///
    /// キャッシュにサムネイルが存在すればそれを即座に返します。
    /// 存在しない場合は、URLから画像データを非同期にダウンロードし、
    /// リサイズしてサムネイルを生成し、キャッシュに保存した上で返します。
    /// - Parameters:
    ///   - url: サムネイルを取得したい画像のURL。
    ///   - maxSize: サムネイルの最大サイズ（幅または高さ）。
    /// - Returns: 生成または取得したサムネイル画像。処理に失敗した場合は`nil`。
    func thumbnail(for url: URL, maxSize: CGFloat = 200) async -> NSImage? {
        // キャッシュに画像があれば即座に返す
        if let cachedImage = image(for: url) {
            return cachedImage
        }

        // ローカルファイルの場合は、同期的に読み込む
        if url.isFileURL {
            guard let image = NSImage(contentsOf: url) else { return nil }
            let thumbnail = image.resized(toMax: maxSize)
            setImage(thumbnail, for: url)
            return thumbnail
        }

        // ネットワーク上のURLの場合は、非同期でダウンロードする
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data) else { return nil }

            let thumbnail = image.resized(toMax: maxSize)
            setImage(thumbnail, for: url)
            return thumbnail
        } catch {
            print("画像のダウンロードに失敗しました: \(error)")
            return nil
        }
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
