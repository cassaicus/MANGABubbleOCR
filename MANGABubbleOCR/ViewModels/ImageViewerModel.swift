import SwiftUI
import Vision
import CoreML

/// アプリケーション全体のUI状態とデータフローを管理する主要なViewModel。
///
/// このクラスは、表示する漫画のページ(`MangaPage`)のリスト、現在の表示位置などを管理し、
/// SwiftUIビューにUIの変更を通知する役割を担います。
class ImageViewerModel: ObservableObject {
    /// アプリケーション全体で共有される唯一のインスタンス（シングルトン）。
    static let shared = ImageViewerModel()

    /// 表示対象となる漫画の全ページ。@Publishedにより、この配列への変更は自動的にUIに通知されます。
    @Published var pages: [MangaPage] = []

    /// 現在表示しているページのインデックス。
    @Published var currentIndex: Int = 0

    /// 外部からの直接的なインスタンス化を防ぐためのプライベートな初期化子。
    private init() {}

    /// 新しいページのリストでモデルを更新します。
    /// - Parameter newPages: 表示する新しい`MangaPage`の配列。
    func setPages(_ newPages: [MangaPage]) {
        self.pages = newPages
        self.currentIndex = 0

        // 新しいページのURLリストを取得し、サムネイルのプリフェッチを開始
        let urls = newPages.map { $0.sourceURL }
        ThumbnailPrefetcher.shared.prefetchThumbnails(for: urls)
    }

    /// 指定されたフォルダから画像を非同期で読み込み、ページのリストを更新します。
    /// - Parameter folder: 画像が含まれるフォルダのURL。
    func loadFolder(_ folder: URL) {
        ImageRepository.shared.fetchLocalImagesAsync(from: folder) { [weak self] urls in
            // URLの配列をMangaPageの配列に変換
            let newPages = urls.map { MangaPage(sourceURL: $0) }

            DispatchQueue.main.async {
                self?.setPages(newPages)
            }
        }
    }

    /// フォルダ選択ダイアログを表示し、ユーザーが選択したフォルダから画像を読み込みます。
    func selectAndLoadFolder() {
        // 新しいフォルダを選択する前に、進行中のプリフェッチをキャンセル
        ThumbnailPrefetcher.shared.cancelAll()

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            loadFolder(url)
        }
    }

    // MARK: - Core ML and Vision Integration

    /// 現在表示されている画像からセリフのフキダシを検出し、一時ファイルとして保存します。
    func analyzeCurrentImageForTextBubbles() {
        // 現在のページが存在するか確認
        guard currentIndex < pages.count else {
            print("現在のページが見つかりません。")
            return
        }
        let currentPage = pages[currentIndex]
        let imageURL = currentPage.sourceURL

        // isProcessing = true // 処理中のUIフィードバック用フラグ（必要に応じて追加）

        Task {
            // ImageCacheからフルサイズの画像を非同期で取得
            guard let nsImage = await ImageCache.shared.fullImage(for: imageURL),
                  let cgImage = nsImage.cgImage() else {
                print("画像の読み込みまたはCGImageへの変換に失敗しました。")
                // isProcessing = false
                return
            }

            // Visionリクエストを実行
            performVisionRequest(with: cgImage)
        }
    }

    /// Visionリクエストを実行して、画像内のオブジェクト（フキダシ）を検出します。
    /// - Parameter cgImage: 分析対象のCGImage。
    private func performVisionRequest(with cgImage: CGImage) {
        do {
            // Core MLモデルのURLを取得
            guard let modelURL = Bundle.main.url(forResource: "best", withExtension: "mlmodelc") else {
                print("モデルファイル(best.mlmodelc)が見つかりません。")
                return
            }

            // モデルをロードしてVisionリクエストを作成
            let mlModel = try MLModel(contentsOf: modelURL)
            let vnModel = try VNCoreMLModel(for: mlModel)

            let request = VNCoreMLRequest(model: vnModel) { [weak self] request, error in
                if let error = error {
                    print("Visionリクエストエラー: \(error)")
                    return
                }

                guard let results = request.results as? [VNRecognizedObjectObservation] else { return }

                let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
                var count = 0

                // 結果をループして、検出されたオブジェクトを処理
                for obs in results {
                    guard let topLabel = obs.labels.first else { continue }

                    let rect = obs.boundingBox
                        .toPixelRectFlipped(in: imageSize)
                        .integralWithin(imageSize: imageSize)

                    if let cropped = cgImage.cropping(to: rect) {
                        self?.saveCroppedImage(cropped, index: count, label: topLabel.identifier, confidence: topLabel.confidence)
                        count += 1
                    }
                }
                print("保存されたフキダシの数: \(count)")
            }

            request.imageCropAndScaleOption = .scaleFit

            // 画像リクエストハンドラを作成して実行
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            try handler.perform([request])

        } catch {
            print("モデルの読み込みまたは推論エラー: \(error)")
        }
    }

    /// 切り抜いた画像を一時ディレクトリに保存します。
    /// - Parameters:
    ///   - cgImage: 保存するCGImage。
    ///   - index: 画像のインデックス（ファイル名に使用）。
    ///   - label: 検出されたオブジェクトのラベル。
    ///   - confidence: 検出の信頼度。
    private func saveCroppedImage(_ cgImage: CGImage, index: Int, label: String, confidence: Float) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cropped_bubbles")
        do {
            // 一時ディレクトリが存在しない場合は作成
            if !FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            }

            let fileName = "cropped_\(index)_\(label)_\(String(format: "%.2f", confidence)).png"
            let fileURL = tempDir.appendingPathComponent(fileName)

            // 既存のファイルを削除
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }

            // CGImageをPNGとして保存（VisionExtensions.swiftの拡張機能を使用）
            try cgImage.save(to: fileURL)
            print("画像を保存しました: \(fileURL.path)")

        } catch {
            print("切り抜いた画像の保存に失敗しました: \(error)")
        }
    }
}
