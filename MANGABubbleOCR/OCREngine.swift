import Foundation
import CoreML
import AppKit

/// 画像の正規化方法を指定するenum
enum NormalizationType {
    case scaleTo_0_1   // [0, 1] にスケーリング（オリジナル）
    case scaleTo_minus1_1 // [-1, 1] にスケーリング（改良版）
}

class OCREngine {
    private var vocab: [Int: String] = [:]
    private let model: manga_ocr

    init?() {
        // staticメソッドで語彙を読み込む。これによりselfが使われる前に呼び出せる。
        guard let loadedVocab = OCREngine.loadVocab() else {
            print("OCREngine Error: vocab.txtの読み込みに失敗しました")
            return nil
        }

        // 全てのプロパティを初期化する
        self.vocab = loadedVocab
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all // GPU/ANEを最大限活用
            self.model = try manga_ocr(configuration: config)
        } catch {
            print("OCREngine Error: manga_ocrモデルの読み込みに失敗しました: \(error)")
            return nil
        }
    }

    /// CGImageを受け取り、OCR結果の文字列を返す
    func recognizeText(from cgImage: CGImage, normalization: NormalizationType) -> String {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        do {
            // 画像をモデルの入力形式(MLMultiArray)に変換
            guard let pixelValues = try imageToMLMultiArray(nsImage: nsImage, size: CGSize(width: 224, height: 224), normalization: normalization) else {
                return "[OCR Error: 画像の変換に失敗しました]"
            }

            let bosTokenId: Int32 = 2 // Begin-of-sequence
            let eosTokenId: Int32 = 3 // End-of-sequence
            let maxLength = 64

            var tokenIds: [Int32] = [bosTokenId]

            // トークンを1つずつ生成するループ
            for _ in 0..<maxLength {
                let decoderInput = try MLMultiArray(shape: [1, NSNumber(value: tokenIds.count)], dataType: .int32)
                for (i, id) in tokenIds.enumerated() {
                    decoderInput[i] = NSNumber(value: id)
                }

                let input = manga_ocrInput(pixel_values: pixelValues, decoder_input_ids: decoderInput)
                let output = try model.prediction(input: input)

                guard let logits = output.var_1114 as? MLMultiArray else {
                    return "[OCR Error: 想定外のモデル出力形式です]"
                }

                // 最も確率の高いトークンIDを取得 (Argmax)
                let vocabSize = logits.shape.last!.intValue
                let lastLogitsStartIndex = logits.count - vocabSize
                var maxId: Int32 = -1
                var maxVal: Float = -Float.infinity
                for v in 0..<vocabSize {
                    let val = logits[lastLogitsStartIndex + v].floatValue
                    if val > maxVal {
                        maxVal = val
                        maxId = Int32(v)
                    }
                }

                tokenIds.append(maxId)
                if maxId == eosTokenId {
                    break // End-of-sequenceトークンが出たら終了
                }
            }

            // トークンIDのシーケンスを文字列にデコード
            let decoded = decodeTokens(tokenIds, bosId: bosTokenId, eosId: eosTokenId, padId: 0)
            return decoded

        } catch {
            return "[OCR Error: \(error.localizedDescription)]"
        }
    }

    private static func loadVocab() -> [Int: String]? {
        guard let url = Bundle.main.url(forResource: "vocab", withExtension: "txt") else {
            print("vocab.txt が見つかりません")
            return nil
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text.components(separatedBy: .newlines)
            var vocabDict: [Int: String] = [:]
            for (i, token) in lines.enumerated() {
                if !token.isEmpty {
                    vocabDict[i] = token
                }
            }
            return vocabDict
        } catch {
            print("vocab.txt 読み込みエラー: \(error)")
            return nil
        }
    }

    private func decodeTokens(_ tokens: [Int32], bosId: Int32, eosId: Int32, padId: Int32) -> String {
        var result = ""
        for id in tokens {
            if id == bosId || id == eosId || id == padId {
                continue
            }
            if let token = self.vocab[Int(id)] {
                result += token
            } else {
                result += "�" // 不明なトークン
            }
        }
        return result.replacingOccurrences(of: "##", with: "")
    }

    private func imageToMLMultiArray(nsImage: NSImage, size: CGSize, normalization: NormalizationType) throws -> MLMultiArray? {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: Int(size.width) * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        guard let resizedImage = context.makeImage() else { return nil }

        let array = try MLMultiArray(shape: [1, 3, 224, 224], dataType: .float32)
        let width = resizedImage.width
        let height = resizedImage.height
        let bytesPerRow = resizedImage.bytesPerRow
        let pixelData = resizedImage.dataProvider!.data!
        let data = CFDataGetBytePtr(pixelData)!

        // (3, 224, 224)のPlanar形式に変換
        var index = 0
        for c in 0..<3 { // RGB
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * bytesPerRow + x * 4
                    let pixelValue = Float(data[pixelIndex + c]) / 255.0 // [0, 1] に正規化

                    var finalValue: Float
                    switch normalization {
                    case .scaleTo_0_1:
                        finalValue = pixelValue
                    case .scaleTo_minus1_1:
                        finalValue = (pixelValue - 0.5) / 0.5 // [-1, 1] にスケーリング
                    }

                    array[index] = NSNumber(value: finalValue)
                    index += 1
                }
            }
        }
        return array
    }
}
