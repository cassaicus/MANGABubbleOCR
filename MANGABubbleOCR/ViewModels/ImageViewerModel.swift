import SwiftUI
import Vision
import CoreML
import CoreData
import AppKit // For NSBitmapImageRep

/**
 `ImageViewerModel` is the primary ViewModel that manages the application's UI state and data flow for manga viewing and analysis.
 `ImageViewerModel`は、漫画の表示と分析に関するアプリケーションのUI状態とデータフローを管理する主要なViewModelです。

 This class is responsible for:
 このクラスは以下の責務を負います:
 - Holding the list of `MangaPage` objects to be displayed.
   表示対象となる`MangaPage`オブジェクトのリストを保持します。
 - Tracking the current page index.
   現在のページインデックスを追跡します。
 - Interacting with Core Data to persist and retrieve manga, page, and text bubble information.
   Core Dataと連携し、漫画、ページ、フキダシの情報を永続化および取得します。
 - Orchestrating the bubble detection process using the Vision framework.
   Visionフレームワークを使用してフキダシ検出プロセスを統括します。
 - Coordinating with `OCREngine` to perform text recognition on detected bubbles.
   `OCREngine`と連携し、検出されたフキダシのテキスト認識を実行します。

 It is implemented as a singleton to provide a single, shared instance across the entire application.
 UI updates are triggered using `@Published` properties, which notify SwiftUI views of any changes.
 シングルトンとして実装されており、アプリケーション全体で単一の共有インスタンスを提供します。
 `@Published`プロパティを使用してUIの更新をトリガーし、SwiftUIビューに変更を通知します。
*/
class ImageViewerModel: ObservableObject {

    // MARK: - Singleton Instance

    /// The shared singleton instance of `ImageViewerModel`.
    /// `ImageViewerModel`の共有シングルトンインスタンス。
    static let shared = ImageViewerModel()
    
    // MARK: - Published Properties

    /// The array of all manga pages currently loaded.
    /// Changes to this array will trigger UI updates in subscribed SwiftUI views.
    /// 現在ロードされている全ての漫画ページの配列。
    /// この配列への変更は、関連するSwiftUIビューのUI更新をトリガーします。
    @Published var pages: [MangaPage] = []

    /// The index of the currently displayed page within the `pages` array.
    /// `pages`配列内での現在表示ページのインデックス。
    @Published var currentIndex: Int = 0

    // MARK: - Core Components

    /// The main-thread `NSManagedObjectContext` for all Core Data operations.
    /// 全てのCore Data操作に使用するメインスレッドの`NSManagedObjectContext`。
    private let viewContext = PersistenceController.shared.container.viewContext

    /// A reference to the OCR engine.
    /// OCRエンジンへの参照。
    private let ocrEngine: OCREngine

    // MARK: - Constants

    private enum Constants {
        static let bubbleDetectorModelName = "best"
        static let bubbleDetectorModelExtension = "mlmodelc"
        static let ocrEngineIdentifier = "MangaOCR-v1.0"
        static let ocrEngineIdentifierRetry = "MangaOCR-v1.0-retry"
        static let ocrFailureIdentifier = "failure"
        static let failedOCRSamplesDirectory = "failed_ocr_samples"
    }

    // MARK: - Initialization

    /// Private initializer to enforce the singleton pattern.
    /// シングルトンパターンを強制するためのプライベートイニシャライザ。
    ///
    /// This attempts to initialize the `OCREngine`. If the engine fails to load
    /// (e.g., model or vocabulary file is missing), the application will terminate
    /// with a fatal error, as OCR is a critical feature.
    /// `OCREngine`の初期化を試みます。エンジンのロードに失敗した場合（例：モデルや語彙ファイルが見つからない）、
    /// OCRは重要な機能であるため、アプリケーションは致命的なエラーで終了します。
    private init() {
        do {
            self.ocrEngine = try OCREngine()
        } catch {
            // In a production app, you might want to handle this more gracefully,
            // for example, by disabling OCR-related features in the UI.
            // 製品版アプリでは、UIのOCR関連機能を無効にするなど、より優雅にこのエラーを処理することが望ましいでしょう。
            fatalError("ImageViewerModel: Failed to initialize OCREngine. Error: \(error)")
        }
    }

    // MARK: - Public Methods for Page Management

    /// Updates the model with a new list of pages.
    /// モデルを新しいページのリストで更新します。
    /// - Parameter newPages: The new array of `MangaPage` objects to display. / 表示する新しい`MangaPage`オブジェクトの配列。
    func setPages(_ newPages: [MangaPage]) {
        self.pages = newPages
        self.currentIndex = 0
        let urls = newPages.map { $0.sourceURL }
        // Start prefetching thumbnails for the new pages in the background.
        // バックグラウンドで新しいページのサムネイルのプリフェッチを開始します。
        ThumbnailPrefetcher.shared.prefetchThumbnails(for: urls)
    }

    /// Asynchronously loads images from a specified folder URL and updates the pages list.
    /// 指定されたフォルダURLから画像を非同期でロードし、ページのリストを更新します。
    /// - Parameter folder: The URL of the folder containing the image files. / 画像ファイルを含むフォルダのURL。
    func loadFolder(_ folder: URL) {
        ImageRepository.shared.fetchLocalImagesAsync(from: folder) { [weak self] urls in
            let newPages = urls.map { MangaPage(sourceURL: $0) }
            DispatchQueue.main.async {
                self?.setPages(newPages)
            }
        }
    }

    /// Displays a folder selection dialog and loads the images from the chosen folder.
    /// フォルダ選択ダイアログを表示し、選択されたフォルダから画像をロードします。
    func selectAndLoadFolder() {
        // Cancel any ongoing prefetching before loading a new folder.
        // 新しいフォルダをロードする前に、進行中のプリフェッチ処理をキャンセルします。
        ThumbnailPrefetcher.shared.cancelAll()

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            loadFolder(url)
        }
    }

    // MARK: - Bubble Analysis and OCR Orchestration

    /// Initiates the text bubble analysis for the currently displayed image.
    /// 現在表示されている画像に対してフキダシ分析を開始します。
    func analyzeCurrentImageForTextBubbles() {
        guard currentIndex < pages.count else { return }
        let currentPage = pages[currentIndex]
        let imageURL = currentPage.sourceURL

        Task {
            guard let nsImage = await ImageCache.shared.fullImage(for: imageURL),
                  let cgImage = nsImage.cgImage(),
                  let imageData = nsImage.tiffRepresentation else {
                print("Error: Failed to load image or convert it to data for analysis.")
                return
            }
            // Hand off to the Vision request performer.
            // Visionリクエスト実行担当に処理を渡します。
            performVisionRequest(with: cgImage, imageData: imageData, originalFileName: imageURL.lastPathComponent)
        }
    }

    /// Performs a Vision request to detect text bubbles in the given image.
    /// 指定された画像内のフキダシを検出するためのVisionリクエストを実行します。
    ///
    /// This method uses a pre-trained Core ML model (`best.mlmodelc`) to find objects
    /// that are classified as text bubbles. The results are then passed to the saving logic.
    /// このメソッドは、事前に訓練されたCore MLモデル（`best.mlmodelc`）を使用して、フキダシとして分類されるオブジェクトを見つけます。
    /// 結果は保存ロジックに渡されます。
    private func performVisionRequest(with cgImage: CGImage, imageData: Data, originalFileName: String) {
        guard let modelURL = Bundle.main.url(forResource: Constants.bubbleDetectorModelName, withExtension: Constants.bubbleDetectorModelExtension) else {
            print("Error: Bubble detector model file not found.")
            return
        }

        do {
            let vnModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let request = VNCoreMLRequest(model: vnModel) { [weak self] request, error in
                if let error = error {
                    print("Vision request failed: \(error.localizedDescription)")
                    return
                }
                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    print("Vision request completed but returned no results or an unexpected type.")
                    return
                }
                self?.processVisionResults(results, forImage: cgImage, imageData: imageData, originalFileName: originalFileName)
            }
            request.imageCropAndScaleOption = .scaleFit

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            try handler.perform([request])
        } catch {
            print("Error: Failed to load VNCoreMLModel or perform request: \(error.localizedDescription)")
        }
    }
    
    /// Processes the results from the Vision request, creating and saving bubble entities.
    /// Visionリクエストからの結果を処理し、フキダシエンティティを作成・保存します。
    ///
    /// This method orchestrates the entire process of saving bubble data:
    /// このメソッドは、フキダシデータを保存するプロセス全体を統括します:
    /// 1. Uses a `DispatchGroup` to coordinate multiple asynchronous OCR tasks.
    ///    `DispatchGroup`を使用して、複数の非同期OCRタスクを調整します。
    /// 2. Performs all Core Data operations on the correct `viewContext` queue.
    ///    全てのCore Data操作を正しい`viewContext`キューで実行します。
    /// 3. Fetches or creates the `Page` entity for the image.
    ///    画像に対応する`Page`エンティティを取得または作成します。
    /// 4. Deletes any old bubbles associated with the page.
    ///    ページに関連する古いフキダシを削除します。
    /// 5. Iterates through detected bubbles, creating `BubbleEntity` objects and dispatching OCR tasks.
    ///    検出されたフキダシをループ処理し、`BubbleEntity`オブジェクトを作成してOCRタスクをディスパッチします。
    /// 6. Saves the Core Data context once all OCR tasks are complete.
    ///    全てのOCRタスクが完了したら、Core Dataコンテキストを保存します。
    private func processVisionResults(_ results: [VNRecognizedObjectObservation], forImage cgImage: CGImage, imageData: Data, originalFileName: String) {
        let ocrDispatchGroup = DispatchGroup()

        // All subsequent Core Data operations must be on the context's queue.
        // これ以降のCore Data操作はすべてコンテキストのキューで実行する必要があります。
        viewContext.perform {
            let page = self.fetchOrCreatePage(with: DataHasher.computeSHA256(for: imageData), originalFileName: originalFileName)
            
            // Clear out any previously detected bubbles for this page.
            // このページに以前検出されたフキダシをクリアします。
            if let existingBubbles = page.bubbles as? NSSet {
                existingBubbles.forEach { self.viewContext.delete($0 as! NSManagedObject) }
            }
            
            // Process each detected bubble.
            // 検出された各フキダシを処理します。
            for observation in results {
                self.createAndProcessBubble(
                    from: observation,
                    in: cgImage,
                    page: page,
                    dispatchGroup: ocrDispatchGroup
                )
            }

            // After all OCR tasks have been dispatched, set up a notification
            // to save the context to disk when they all complete.
            // 全てのOCRタスクがディスパッチされた後、それらがすべて完了したときに
            // コンテキストをディスクに保存するための通知を設定します。
            ocrDispatchGroup.notify(queue: .main) {
                self.saveContext()
            }
        }
    }

    /// Creates a single `BubbleEntity`, crops its image, and dispatches an OCR task.
    /// 単一の`BubbleEntity`を作成し、その画像を切り出してOCRタスクをディスパッチします。
    private func createAndProcessBubble(from observation: VNRecognizedObjectObservation, in cgImage: CGImage, page: Page, dispatchGroup: DispatchGroup) {
        let newBubble = BubbleEntity(context: self.viewContext)
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let rect = observation.boundingBox.toPixelRectFlipped(in: imageSize)

        newBubble.bubbleID = UUID()
        newBubble.x = rect.origin.x
        newBubble.y = rect.origin.y
        newBubble.width = rect.size.width
        newBubble.height = rect.size.height
        newBubble.page = page
        newBubble.shouldOcr = true
        newBubble.ocrStatus = "pending"

        guard newBubble.shouldOcr, let croppedCGImage = cgImage.cropping(to: rect) else {
            newBubble.ocrStatus = "skipped"
            return
        }

        // Dispatch an asynchronous OCR task for the cropped image.
        // 切り出した画像に対して非同期のOCRタスクをディスパッチします。
        dispatchGroup.enter()
        runOCR(on: croppedCGImage, for: newBubble.objectID, with: newBubble.bubbleID!) {
            dispatchGroup.leave()
        }
    }

    /// Performs OCR on a single cropped image and updates the corresponding `BubbleEntity`.
    /// 切り出された単一の画像に対してOCRを実行し、対応する`BubbleEntity`を更新します。
    ///
    /// This method includes a retry mechanism: if OCR fails with the primary normalization
    /// method or returns an empty result, it attempts again with a secondary method.
    /// If the second attempt also fails, the cropped image is saved to a temporary directory for debugging.
    /// このメソッドは再試行メカニズムを含みます：プライマリ正規化手法でOCRが失敗した、または空の結果を返した場合、
    /// セカンダリ手法で再試行します。2回目の試行も失敗した場合、切り出された画像はデバッグのために
    /// 一時ディレクトリに保存されます。
    private func runOCR(on cgImage: CGImage, for bubbleObjectID: NSManagedObjectID, with bubbleID: UUID, completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            
            // Helper to perform a single OCR attempt and return a Result.
            // 単一のOCR試行を実行し、Resultを返すヘルパー。
            let performOcrOnce = { (normalization: NormalizationType) -> Result<String, Error> in
                do {
                    // Use the original image directly without cropping.
                    // クロップせずに元の画像を直接使用します。
                    let text = try self.ocrEngine.recognizeText(from: cgImage, normalization: normalization)
                    if text.isEmpty {
                        // Treat empty string as a failure to trigger retry.
                        // 空文字列を失敗として扱い、再試行をトリガーする。
                        return .failure(OCREngineError.unexpectedModelOutput)
                    }
                    return .success(text)
                } catch {
                    return .failure(error)
                }
            }

            var ocrResult: (text: String, identifier: String)

            // 1. First attempt
            // 1. 最初の試行
            let firstAttemptResult = performOcrOnce(.scaleTo_minus1_1)

            switch firstAttemptResult {
            case .success(let text):
                // First attempt succeeded.
                // 最初の試行が成功。
                ocrResult = (text, Constants.ocrEngineIdentifier)

            case .failure(let error):
                // First attempt failed, try second attempt.
                // 最初の試行が失敗、2回目の試行へ。
                print("OCR failed or returned empty with primary normalization, retrying... Error: \(error.localizedDescription)")
                let secondAttemptResult = performOcrOnce(.scaleTo_0_1)

                switch secondAttemptResult {
                case .success(let text):
                    // Second attempt succeeded.
                    // 2回目の試行が成功。
                    ocrResult = (text, Constants.ocrEngineIdentifierRetry)

                case .failure(let secondError):
                    // Second attempt also failed.
                    // 2回目の試行も失敗。
                    print("OCR failed with secondary normalization. Error: \(secondError.localizedDescription)")
                    ocrResult = ("[\(secondError.localizedDescription)]", Constants.ocrFailureIdentifier)
                    self.saveFailedOCRImage(cgImage, for: bubbleID)
                }
            }

            // Update Core Data on the correct queue.
            // 正しいキューでCore Dataを更新。
            self.viewContext.perform {
                self.updateBubble(bubbleObjectID, with: ocrResult)
                completion()
            }
        }
    }
    
    /// Updates a `BubbleEntity` with the results of an OCR operation.
    /// OCR操作の結果で`BubbleEntity`を更新します。
    /// This method must be called on the `viewContext`'s queue.
    /// このメソッドは`viewContext`のキューで呼び出す必要があります。
    private func updateBubble(_ bubbleObjectID: NSManagedObjectID, with result: (text: String, identifier: String)) {
        guard let bubble = try? self.viewContext.existingObject(with: bubbleObjectID) as? BubbleEntity else {
            return
        }

        let isSuccess = result.identifier != Constants.ocrFailureIdentifier && !result.text.isEmpty

        bubble.ocrText = result.text
        bubble.ocrTimestamp = Date()
        bubble.ocrEngineIdentifier = result.identifier
        bubble.ocrConfidence = isSuccess ? 1.0 : 0.0 // Placeholder confidence / プレースホルダーの信頼度
        bubble.ocrStatus = isSuccess ? "success" : "failure"

        print("OCR Result for bubble [\(bubble.bubbleID!)] with engine [\(result.identifier)]: \(result.text)")
    }

    // MARK: - Core Data Helper Methods

    /// Fetches a `Page` entity with a specific hash from Core Data, or creates one if not found.
    /// 特定のハッシュを持つ`Page`エンティティをCore Dataから取得するか、見つからない場合は新規作成します。
    /// This method must be called on the `viewContext`'s queue.
    /// このメソッドは`viewContext`のキューで呼び出す必要があります。
    private func fetchOrCreatePage(with hash: String, originalFileName: String) -> Page {
        let request: NSFetchRequest<Page> = Page.fetchRequest()
        request.predicate = NSPredicate(format: "fileHash == %@", hash)
        
        if let existingPage = try? viewContext.fetch(request).first {
            return existingPage
        }
        
        let newPage = Page(context: viewContext)
        newPage.pageID = UUID()
        newPage.fileHash = hash
        newPage.originalFileName = originalFileName
        newPage.book = fetchOrCreateBook() // Associate with a book / ブックに関連付ける
        return newPage
    }

    /// Fetches the first `Book` entity or creates a default one if none exist.
    /// 最初の`Book`エンティティを取得するか、存在しない場合はデフォルトのものを作成します。
    /// This method must be called on the `viewContext`'s queue.
    /// このメソッドは`viewContext`のキューで呼び出す必要があります。
    private func fetchOrCreateBook() -> Book {
        let request: NSFetchRequest<Book> = Book.fetchRequest()
        request.fetchLimit = 1
        
        if let existingBook = try? viewContext.fetch(request).first {
            return existingBook
        }
        
        let newBook = Book(context: viewContext)
        newBook.bookID = UUID()
        newBook.title = "Default Book"
        return newBook
    }

    /// Saves the Core Data context if there are changes.
    /// 変更がある場合にCore Dataコンテキストを保存します。
    private func saveContext() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
            print("Successfully saved bubbles and OCR results to Core Data.")
        } catch {
            print("Failed to save Core Data context: \(error.localizedDescription)")
            // Rollback to discard the failed changes.
            // 失敗した変更を破棄するためにロールバックします。
            viewContext.rollback()
        }
    }

    // MARK: - Filesystem Helper

    /// Creates a temporary directory for storing failed OCR sample images.
    /// OCRに失敗したサンプル画像を保存するための一時ディレクトリを作成します。
    /// - Returns: The URL of the created directory, or `nil` on failure.
    ///   作成されたディレクトリのURL。失敗した場合は`nil`。
    private func setupTemporaryDirectory() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(Constants.failedOCRSamplesDirectory)
        do {
            // Create directory if it doesn't exist.
            // ディレクトリが存在しない場合は作成します。
            if !FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            }
            return tempDir
        } catch {
            print("Failed to create temporary directory: \(error.localizedDescription)")
            return nil
        }
    }

    /// Saves a `CGImage` to a PNG file in the temporary directory.
    /// `CGImage`を一時ディレクトリにPNGファイルとして保存します。
    /// - Parameters:
    ///   - cgImage: The image to save. / 保存する画像。
    ///   - bubbleID: The UUID of the bubble, used for the filename. / ファイル名として使用されるフキダシのUUID。
    private func saveFailedOCRImage(_ cgImage: CGImage, for bubbleID: UUID) {
        guard let tempDir = setupTemporaryDirectory() else { return }
        let fileName = "\(bubbleID).png"
        let fileURL = tempDir.appendingPathComponent(fileName)

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            print("Failed to convert cgImage to PNG data for bubble \(bubbleID)")
            return
        }

        do {
            try pngData.write(to: fileURL)
            print("Saved failed OCR sample to: \(fileURL.path)")
        } catch {
            print("Failed to save failed OCR sample: \(error.localizedDescription)")
        }
    }
}
