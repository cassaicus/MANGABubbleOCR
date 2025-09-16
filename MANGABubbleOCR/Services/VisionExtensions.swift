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

    /// 画像の透明な余白をトリミングします。
    ///
    /// このメソッドは、画像のピクセルデータをスキャンして、完全に透明ではない最初のピクセルと
    /// 最後のピクセルを見つけ出し、その領域を囲む新しい画像を返します。
    /// もし画像が完全に透明であるか、処理に失敗した場合は、元の画像を返します。
    /// - Returns: トリミングされた新しい `CGImage`、または元の画像。
    func trimmingWhitespace() -> CGImage {
        // 1. 画像のピクセルデータにアクセスするためのビットマップコンテキストを作成します。
        guard let context = CGContext(
            data: nil,
            width: self.width,
            height: self.height,
            bitsPerComponent: 8,
            bytesPerRow: self.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            // コンテキストが作成できない場合は、安全のために元の画像を返します。
            return self
        }

        // コンテキストに画像をレンダリングします。
        context.draw(self, in: CGRect(x: 0, y: 0, width: self.width, height: self.height))

        // 2. ピクセルデータのバッファへのポインタを取得します。
        // 各ピクセルは32ビット（RGBA）で表されます。
        guard let data = context.data?.bindMemory(to: UInt32.self, capacity: self.width * self.height) else {
            return self
        }

        // 3. 不透明なピクセルが含まれる領域（バウンディングボックス）を見つけます。
        var minX = self.width
        var minY = self.height
        var maxX = -1
        var maxY = -1

        for y in 0 ..< self.height {
            for x in 0 ..< self.width {
                // ピクセルのアルファ値を取得します。
                // RGBAフォーマットなので、アルファ値は最上位バイトにあります。
                let alpha = (data[y * self.width + x] >> 24) & 0xFF

                // 4. アルファ値が0より大きい（完全に透明ではない）場合、
                // バウンディングボックスを更新します。
                if alpha > 0 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        // 5. 不透明なピクセルが見つかった場合のみ、画像をクロップします。
        if maxX > minX && maxY > minY {
            let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            // `cropping(to:)` は失敗する可能性があるため、オプショナルを返します。
            // 失敗した場合は、安全のために元の画像を返します。
            return self.cropping(to: cropRect) ?? self
        } else {
            // 画像が完全に透明か、何も見つからなかった場合は、元の画像を返します。
            return self
        }
    }
}
