import Foundation
import CoreML
import AppKit

/// An enumeration defining the possible normalization methods for image data.
/// The OCR model may perform differently based on the normalization used.
enum NormalizationType {
    /// Scales pixel values to the range [0, 1]. This was the original method.
    case scaleTo_0_1
    /// Scales pixel values to the range [-1, 1]. This is an improved method.
    case scaleTo_minus1_1
}

/// Defines custom errors that can be thrown by the OCREngine.
enum OCREngineError: Error {
    case vocabFileNotFound
    case vocabFileReadError(Error)
    case modelLoadError(Error)
    case imageConversionError
    case unexpectedModelOutput
    case predictionError(Error)
}

/// `OCREngine` encapsulates the `manga_ocr` Core ML model and provides a simple interface
/// to perform Optical Character Recognition on images. It handles model loading,
/// vocabulary management, image preprocessing, and text generation.
class OCREngine {

    // MARK: - Properties

    /// A dictionary mapping token IDs to their string representation.
    private var vocab: [Int: String]

    /// The underlying Core ML model for OCR.
    private let model: manga_ocr

    // MARK: - Constants

    private enum Constants {
        static let bosTokenId: Int32 = 2 // Begin-of-sequence token ID
        static let eosTokenId: Int32 = 3 // End-of-sequence token ID
        static let padTokenId: Int32 = 0 // Padding token ID
        static let maxTokenLength = 64
        static let modelImageSize = CGSize(width: 224, height: 224)
        static let vocabResourceName = "vocab"
        static let vocabResourceExtension = "txt"
    }

    // MARK: - Initialization

    /// Initializes the `OCREngine`.
    ///
    /// This initializer can fail if the vocabulary file (`vocab.txt`) cannot be loaded
    /// or if the Core ML model (`manga_ocr.mlmodel`) fails to initialize.
    /// It loads the vocabulary and sets up the model with a configuration that
    /// utilizes all available compute units (GPU, ANE) for maximum performance.
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
    ///
    /// This is the main public method of the class. It takes an image, preprocesses it,
    /// runs it through the generative OCR model, and decodes the resulting token sequence
    /// into a human-readable string.
    ///
    /// - Parameter cgImage: The image to perform OCR on.
    /// - Parameter normalization: The normalization method to use for preprocessing.
    /// - Returns: The recognized text as a `String`.
    /// - Throws: An `OCREngineError` if any step of the process fails.
    func recognizeText(from cgImage: CGImage, normalization: NormalizationType) throws -> String {
        // 1. Preprocess the image into the format expected by the model.
        guard let pixelValues = try imageToMLMultiArray(
            cgImage: cgImage,
            size: Constants.modelImageSize,
            normalization: normalization
        ) else {
            throw OCREngineError.imageConversionError
        }

        // 2. Generate a sequence of token IDs from the image.
        let tokenIds = try generateTokenSequence(from: pixelValues)

        // 3. Decode the token IDs into a string.
        let decodedText = decodeTokens(tokenIds)

        return decodedText
    }

    // MARK: - Private Helper Methods

    /// Generates a sequence of text tokens from the preprocessed image data.
    ///
    /// This method implements an auto-regressive generation loop. It starts with a
    /// "begin-of-sequence" token and repeatedly feeds the model with the current sequence
    /// to predict the next token, until an "end-of-sequence" token is produced or the
    /// maximum length is reached.
    ///
    /// - Parameter pixelValues: The preprocessed image data as an `MLMultiArray`.
    /// - Returns: An array of generated token IDs.
    /// - Throws: An `OCREngineError` if the model prediction fails or returns an unexpected format.
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

            guard let logits = output.var_1114 as? MLMultiArray else {
                throw OCREngineError.unexpectedModelOutput
            }

            // Find the token with the highest probability (argmax).
            let nextTokenId = argmax(logits: logits)
            tokenIds.append(nextTokenId)

            if nextTokenId == Constants.eosTokenId {
                break
            }
        }
        return tokenIds
    }

    /// Finds the index of the maximum value in the final dimension of the logits tensor.
    ///
    /// - Parameter logits: The `MLMultiArray` output from the model's final layer.
    /// - Returns: The token ID with the highest probability.
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
    ///
    /// - Parameter tokens: An array of token IDs to decode.
    /// - Returns: The decoded string.
    private func decodeTokens(_ tokens: [Int32]) -> String {
        var result = ""
        for id in tokens {
            // Ignore special tokens (start, end, padding).
            if id == Constants.bosTokenId || id == Constants.eosTokenId || id == Constants.padTokenId {
                continue
            }

            if let token = self.vocab[Int(id)] {
                result += token
            } else {
                result += "�" // Replacement character for unknown tokens.
            }
        }
        // The model uses "##" to denote sub-word tokens, which should be merged.
        return result.replacingOccurrences(of: "##", with: "")
    }

    /// Loads the vocabulary from the `vocab.txt` file in the main bundle.
    ///
    /// - Returns: A dictionary mapping token IDs (integers) to tokens (strings).
    /// - Throws: `OCREngineError` if the file is not found or cannot be read.
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
    ///
    /// This function performs two main tasks:
    /// 1. Resizes the image to the required input dimensions of the model (224x224).
    /// 2. Converts the pixel data into a planar (C, H, W) `MLMultiArray` and normalizes the values.
    ///
    /// - Parameters:
    ///   - cgImage: The source image.
    ///   - size: The target size for the image (e.g., 224x224).
    ///   - normalization: The normalization method to apply to pixel values.
    /// - Returns: A 4D `MLMultiArray` with shape [1, 3, height, width], or `nil` if conversion fails.
    /// - Throws: An error if the `MLMultiArray` cannot be created.
    private func imageToMLMultiArray(cgImage: CGImage, size: CGSize, normalization: NormalizationType) throws -> MLMultiArray? {
        // 1. Resize the image
        guard let resizedImage = cgImage.resized(to: size) else {
            return nil
        }

        // 2. Convert to MLMultiArray and normalize
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: size.height), NSNumber(value: size.width)], dataType: .float32)

        let width = resizedImage.width
        let height = resizedImage.height
        let bytesPerRow = resizedImage.bytesPerRow
        let pixelData = resizedImage.dataProvider!.data!
        let data = CFDataGetBytePtr(pixelData)!

        var index = 0
        // The model expects a planar layout (all R values, then all G, then all B).
        for channel in 0..<3 { // R, G, B
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * bytesPerRow + x * 4
                    // The raw pixel data is in RGBA format.
                    let byte = data[pixelIndex + channel]
                    let normalizedValue = Float(byte) / 255.0 // Normalize to [0, 1]

                    var finalValue: Float
                    switch normalization {
                    case .scaleTo_0_1:
                        finalValue = normalizedValue
                    case .scaleTo_minus1_1:
                        // Scale from [0, 1] to [-1, 1]
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
    /// - Parameter size: The target `CGSize`.
    /// - Returns: A new, resized `CGImage`, or `nil` if resizing fails.
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
