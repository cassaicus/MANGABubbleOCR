import SwiftUI
import Vision

// NSImageからCGImageへの変換
extension NSImage {
    /// NSImageからCGImageを生成します。
    /// - Returns: 変換されたCGImage、失敗した場合はnil。
    func cgImage() -> CGImage? {
        var imageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        return cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }
}

// Visionの正規化された座標をUIKit/AppKitの座標系に変換
extension CGRect {
    /// Visionフレームワークから返される正規化された矩形（Y軸が反転）を、
    /// 画像のピクセル単位の矩形に変換します。
    /// - Parameter imageSize: 変換の基準となる画像のサイズ。
    /// - Returns: ピクセル単位に変換されたCGRect。
    func toPixelRectFlipped(in imageSize: CGSize) -> CGRect {
        let x = self.origin.x * imageSize.width
        let y = (1 - self.origin.y - self.height) * imageSize.height
        let width = self.width * imageSize.width
        let height = self.height * imageSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 矩形の座標を整数値に丸め、画像の境界内に収まるように調整します。
    /// - Parameter imageSize: 矩形が収まるべき画像のサイズ。
    /// - Returns: 調整された整数座標のCGRect。
    func integralWithin(imageSize: CGSize) -> CGRect {
        let integralRect = self.integral
        let safeRect = integralRect.intersection(CGRect(origin: .zero, size: imageSize))
        return safeRect
    }
}

// CGImageの保存用拡張
extension CGImage {
    /// CGImageをPNG形式で指定されたURLに保存します。
    /// - Parameter url: 保存先のファイルURL。
    /// - Throws: 保存に失敗した場合にエラーをスローします。
    func save(to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else {
            throw NSError(domain: "ImageSaveError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create destination."])
        }
        CGImageDestinationAddImage(destination, self, nil)
        if !CGImageDestinationFinalize(destination) {
            throw NSError(domain: "ImageSaveError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image."])
        }
    }

    /// 画像の端から指定されたピクセル数だけクロップ（切り取り）します。
    /// - Parameter inset: 各辺から切り取るピクセル数。
    /// - Returns: クロップされた新しい `CGImage`。クロップ後のサイズが0以下になる場合は元の画像を返します。
    func cropping(by inset: CGFloat) -> CGImage {
        let newWidth = CGFloat(self.width) - inset * 2
        let newHeight = CGFloat(self.height) - inset * 2

        // クロップ後の幅や高さが0以下にならないようにチェックします。
        if newWidth <= 0 || newHeight <= 0 {
            return self
        }

        let cropRect = CGRect(x: inset, y: inset, width: newWidth, height: newHeight)

        // `cropping(to:)` は失敗する可能性があるため、オプショナルを返します。
        // 失敗した場合は、安全のために元の画像を返します。
        return self.cropping(to: cropRect) ?? self
    }
}
