import Foundation
import CoreML
import AppKit

/// An enumeration defining the possible normalization methods for image data.
/// The OCR model may perform differently based on the normalization used.
/// 画像データの正規化方法を定義する列挙型。
/// OCRモデルは使用される正規化によって性能が異なる場合があります。
enum NormalizationType {
    /// Scales pixel values to the range [0, 1]. This was the original method.
    /// ピクセル値を[0, 1]の範囲にスケーリングします。これは元の方法です。
    case scaleTo_0_1
    /// Scales pixel values to the range [-1, 1]. This is an improved method.
    /// ピクセル値を[-1, 1]の範囲にスケーリングします。これは改良された方法です。
    case scaleTo_minus1_1
}

/// Defines custom errors that can be thrown by the OCREngine.
/// OCREngineからスローされる可能性のあるカスタムエラーを定義します。
enum OCREngineError: Error {
    /// The vocabulary file (`vocab.txt`) was not found in the bundle.
    /// 語彙ファイル(`vocab.txt`)がバンドルに見つかりませんでした。
    case vocabFileNotFound
    /// Failed to read the vocabulary file.
    /// 語彙ファイルの読み込みに失敗しました。
    case vocabFileReadError(Error)
    /// The Core ML model failed to load.
    /// Core MLモデルのロードに失敗しました。
    case modelLoadError(Error)
    /// Failed to convert the input `CGImage` to the required `MLMultiArray` format.
    /// 入力`CGImage`を要求される`MLMultiArray`形式に変換できませんでした。
    case imageConversionError
    /// The model produced an output in an unexpected format.
    /// モデルが予期しない形式の出力を生成しました。
    case unexpectedModelOutput
    /// An error occurred during model prediction.
    /// モデルの予測中にエラーが発生しました。
    case predictionError(Error)
}

/// `OCREngine` encapsulates the `manga_ocr` Core ML model and provides a simple interface
/// to perform Optical Character Recognition on images. It handles model loading,
/// vocabulary management, image preprocessing, and text generation.
/// `OCREngine`は`manga_ocr` Core MLモデルをカプセル化し、画像上で光学文字認識（OCR）を実行するための
/// シンプルなインターフェースを提供します。モデルの読み込み、語彙管理、画像の前処理、テキスト生成を処理します。
class OCREngine {

    // MARK: - Properties

    /// A dictionary mapping token IDs to their string representation.
    /// トークンIDをその文字列表現にマッピングする辞書。
    private var vocab: [Int: String]

    /// The underlying Core ML model for OCR.
    /// OCRのための基盤となるCore MLモデル。
    private let model: manga_ocr

    // MARK: - Constants

    private enum Constants {
        static let bosTokenId: Int32 = 2 // Begin-of-sequence token ID / シーケンス開始トークンID
        static let eosTokenId: Int32 = 3 // End-of-sequence token ID / シーケンス終了トークンID
        static let padTokenId: Int32 = 0 // Padding token ID / パディングトークンID
        static let maxTokenLength = 64
        static let modelImageSize = CGSize(width: 224, height: 224)
        static let vocabResourceName = "vocab"
        static let vocabResourceExtension = "txt"
    }

    // MARK: - Initialization

    /// Initializes the `OCREngine`.
    /// `OCREngine`を初期化します。
    ///
    /// This initializer can fail if the vocabulary file (`vocab.txt`) cannot be loaded
    /// or if the Core ML model (`manga_ocr.mlmodel`) fails to initialize.
    /// It loads the vocabulary and sets up the model with a configuration that
    /// utilizes all available compute units (GPU, ANE) for maximum performance.
    /// このイニシャライザは、語彙ファイル（`vocab.txt`）が読み込めない、またはCore MLモデル（`manga_ocr.mlmodel`）の
    /// 初期化に失敗した場合に失敗することがあります。
    /// 語彙を読み込み、最大限のパフォーマンスを得るために利用可能なすべての計算ユニット（GPU, ANE）を
    /// 活用する構成でモデルをセットアップします。
    init() throws {
        self.vocab = try OCREngine.loadVocab()
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            self.model = try manga_ocr(configuration: config)
        } catch {
            throw OCREngineError.modelLoadError(error)
        }
    }

    // MARK: - Public Methods

    /// Performs OCR on a given `CGImage` and returns the recognized text.
    /// 指定された`CGImage`に対してOCRを実行し、認識されたテキストを返します。
    ///
    /// This is the main public method of the class. It takes an image, preprocesses it,
    /// runs it through the generative OCR model, and decodes the resulting token sequence
    /// into a human-readable string.
    /// これはクラスの主要な公開メソッドです。画像を受け取り、前処理を行い、
    /// 生成的なOCRモデルで実行し、結果のトークンシーケンスを人間が読める文字列にデコードします。
    ///
    /// - Parameter cgImage: The image to perform OCR on. / OCRを実行する画像。
    /// - Parameter normalization: The normalization method to use for preprocessing. / 前処理に使用する正規化手法。
    /// - Returns: The recognized text as a `String`. / 認識されたテキスト（`String`）。
    /// - Throws: An `OCREngineError` if any step of the process fails. / プロセスのいずれかのステップで失敗した場合に`OCREngineError`をスローします。
    func recognizeText(from cgImage: CGImage, normalization: NormalizationType) throws -> String {
        // 1. Preprocess the image into the format expected by the model.
        // 1. モデルが期待する形式に画像を前処理します。
        guard let pixelValues = try imageToMLMultiArray(
            cgImage: cgImage,
            size: Constants.modelImageSize,
            normalization: normalization
        ) else {
            throw OCREngineError.imageConversionError
        }

        // 2. Generate a sequence of token IDs from the image.
        // 2. 画像からトークンIDのシーケンスを生成します。
        let tokenIds = try generateTokenSequence(from: pixelValues)

        // 3. Decode the token IDs into a string.
        // 3. トークンIDを文字列にデコードします。
        let decodedText = decodeTokens(tokenIds)

        return decodedText
    }

    // MARK: - Private Helper Methods

    /// Generates a sequence of text tokens from the preprocessed image data.
    /// 前処理された画像データからテキストトークンのシーケンスを生成します。
    ///
    /// This method implements an auto-regressive generation loop. It starts with a
    /// "begin-of-sequence" token and repeatedly feeds the model with the current sequence
    /// to predict the next token, until an "end-of-sequence" token is produced or the
    /// maximum length is reached.
    /// このメソッドは自己回帰的な生成ループを実装しています。「シーケンス開始」トークンから始まり、
    /// 現在のシーケンスをモデルに繰り返し供給して次のトークンを予測し、「シーケンス終了」トークンが
    /// 生成されるか最大長に達するまで続けます。
    ///
    /// - Parameter pixelValues: The preprocessed image data as an `MLMultiArray`. / 前処理された画像データ（`MLMultiArray`）。
    /// - Returns: An array of generated token IDs. / 生成されたトークンIDの配列。
    /// - Throws: An `OCREngineError` if the model prediction fails or returns an unexpected format. / モデルの予測が失敗したか、予期しない形式を返した場合に`OCREngineError`をスローします。
    private func generateTokenSequence(from pixelValues: MLMultiArray) throws -> [Int32] {
        var tokenIds: [Int32] = [Constants.bosTokenId]

        for _ in 0..<Constants.maxTokenLength {
            let decoderInput = try MLMultiArray(shape: [1, NSNumber(value: tokenIds.count)], dataType: .int32)
            for (i, id) in tokenIds.enumerated() {
                decoderInput[i] = NSNumber(value: id)
            }

            let input = manga_ocrInput(pixel_values: pixelValues, decoder_input_ids: decoderInput)
            let output: manga_ocrOutput
            do {
                output = try model.prediction(input: input)
            } catch {
                throw OCREngineError.predictionError(error)
            }

            guard let logits = output.var_1119 as? MLMultiArray else {
                throw OCREngineError.unexpectedModelOutput
            }

            // Find the token with the highest probability (argmax).
            // 最も確率の高いトークンを見つけます（argmax）。
            let nextTokenId = argmax(logits: logits)
            tokenIds.append(nextTokenId)

            if nextTokenId == Constants.eosTokenId {
                break
            }
        }
        return tokenIds
    }

    /// Finds the index of the maximum value in the final dimension of the logits tensor.
    /// ロジットテンソルの最終次元における最大値のインデックスを見つけます。
    ///
    /// - Parameter logits: The `MLMultiArray` output from the model's final layer. / モデルの最終レイヤーからの`MLMultiArray`出力。
    /// - Returns: The token ID with the highest probability. / 最も確率の高いトークンID。
    private func argmax(logits: MLMultiArray) -> Int32 {
        let vocabSize = logits.shape.last!.intValue
        let lastLogitsStartIndex = logits.count - vocabSize

        var maxId: Int32 = -1
        var maxVal: Float = -Float.infinity

        for i in 0..<vocabSize {
            let val = logits[lastLogitsStartIndex + i].floatValue
            if val > maxVal {
                maxVal = val
                maxId = Int32(i)
            }
        }
        return maxId
    }

    /// Decodes a sequence of token IDs into a string using the vocabulary.
    /// 語彙を使用してトークンIDのシーケンスを文字列にデコードします。
    ///
    /// - Parameter tokens: An array of token IDs to decode. / デコードするトークンIDの配列。
    /// - Returns: The decoded string. / デコードされた文字列。
    private func decodeTokens(_ tokens: [Int32]) -> String {
        var result = ""
        for id in tokens {
            // Ignore special tokens (start, end, padding).
            // 特殊トークン（開始、終了、パディング）は無視します。
            if id == Constants.bosTokenId || id == Constants.eosTokenId || id == Constants.padTokenId {
                continue
            }

            if let token = self.vocab[Int(id)] {
                result += token
            } else {
                result += "�" // Replacement character for unknown tokens. / 不明なトークンのための置換文字。
            }
        }
        // The model uses "##" to denote sub-word tokens, which should be merged.
        // モデルは単語の一部を示すために "##" を使用しており、これらは結合されるべきです。
        return result.replacingOccurrences(of: "##", with: "")
    }

    /// Loads the vocabulary from the `vocab.txt` file in the main bundle.
    /// メインバンドル内の`vocab.txt`ファイルから語彙を読み込みます。
    ///
    /// - Returns: A dictionary mapping token IDs (integers) to tokens (strings). / トークンID（整数）をトークン（文字列）にマッピングする辞書。
    /// - Throws: `OCREngineError` if the file is not found or cannot be read. / ファイルが見つからないか読み取れない場合に`OCREngineError`をスローします。
    private static func loadVocab() throws -> [Int: String] {
        guard let url = Bundle.main.url(forResource: Constants.vocabResourceName, withExtension: Constants.vocabResourceExtension) else {
            throw OCREngineError.vocabFileNotFound
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
            throw OCREngineError.vocabFileReadError(error)
        }
    }

    /// Converts a `CGImage` into an `MLMultiArray` suitable for the Core ML model.
    /// `CGImage`をCore MLモデルに適した`MLMultiArray`に変換します。
    ///
    /// This function performs two main tasks:
    /// この関数は主に2つのタスクを実行します:
    /// 1. Resizes the image to the required input dimensions of the model (224x224).
    ///    画像をモデルが必要とする入力次元（224x224）にリサイズします。
    /// 2. Converts the pixel data into a planar (C, H, W) `MLMultiArray` and normalizes the values.
    ///    ピクセルデータをプレーナー（C, H, W）形式の`MLMultiArray`に変換し、値を正規化します。
    ///
    /// - Parameters:
    ///   - cgImage: The source image. / ソース画像。
    ///   - size: The target size for the image (e.g., 224x224). / 画像のターゲットサイズ（例：224x224）。
    ///   - normalization: The normalization method to apply to pixel values. / ピクセル値に適用する正規化手法。
    /// - Returns: A 4D `MLMultiArray` with shape [1, 3, height, width], or `nil` if conversion fails. / 形状が[1, 3, height, width]の4D `MLMultiArray`。変換に失敗した場合は`nil`。
    /// - Throws: An error if the `MLMultiArray` cannot be created. / `MLMultiArray`の作成に失敗した場合にエラーをスローします。
    private func imageToMLMultiArray(cgImage: CGImage, size: CGSize, normalization: NormalizationType) throws -> MLMultiArray? {
        // 1. Resize the image
        // 1. 画像をリサイズ
        guard let resizedImage = cgImage.resized(to: size) else {
            return nil
        }

        // 2. Convert to MLMultiArray and normalize
        // 2. MLMultiArrayに変換して正規化
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: size.height), NSNumber(value: size.width)], dataType: .float32)

        let width = resizedImage.width
        let height = resizedImage.height
        let bytesPerRow = resizedImage.bytesPerRow
        let pixelData = resizedImage.dataProvider!.data!
        let data = CFDataGetBytePtr(pixelData)!

        var index = 0
        // The model expects a planar layout (all R values, then all G, then all B).
        // モデルはプレーナーレイアウト（すべてのR値、次にすべてのG値、最後にすべてのB値）を期待します。
        for channel in 0..<3 { // R, G, B
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * bytesPerRow + x * 4
                    // The raw pixel data is in RGBA format.
                    // 生のピクセルデータはRGBA形式です。
                    let byte = data[pixelIndex + channel]
                    let normalizedValue = Float(byte) / 255.0 // Normalize to [0, 1] / [0, 1]に正規化

                    var finalValue: Float
                    switch normalization {
                    case .scaleTo_0_1:
                        finalValue = normalizedValue
                    case .scaleTo_minus1_1:
                        // Scale from [0, 1] to [-1, 1]
                        // [0, 1]から[-1, 1]にスケーリング
                        finalValue = (normalizedValue * 2.0) - 1.0
                    }

                    array[index] = NSNumber(value: finalValue)
                    index += 1
                }
            }
        }
        return array
    }
}

// MARK: - CGImage Extension

extension CGImage {
    /// Resizes a `CGImage` to a specified size.
    /// `CGImage`を指定されたサイズにリサイズします。
    /// - Parameter size: The target `CGSize`. / ターゲットの`CGSize`。
    /// - Returns: A new, resized `CGImage`, or `nil` if resizing fails. / 新しいリサイズされた`CGImage`。リサイズに失敗した場合は`nil`。
    func resized(to size: CGSize) -> CGImage? {
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
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}
