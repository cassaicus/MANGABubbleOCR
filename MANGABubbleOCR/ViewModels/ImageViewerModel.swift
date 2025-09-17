import SwiftUI
import Vision
import CoreML
import CoreData
import AppKit // For NSBitmapImageRep
import Translation

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
    /// When the index changes, `updatePageStatus` is called to refresh the UI state.
    /// `pages`配列内での現在表示ページのインデックス。
    /// インデックスが変更されると、`updatePageStatus`が呼び出されてUIの状態が更新されます。
    @Published var currentIndex: Int = 0 {
        didSet {
            if oldValue != currentIndex {
                updatePageStatus()
            }
        }
    }

    /// A flag indicating if bubble extraction is complete for the current page. Bound to the UI.
    /// 現在のページでフキダシ抽出が完了したかどうかを示すフラグ。UIにバインドされます。
    @Published var isExtractionDoneForCurrentPage: Bool = false

    /// A flag indicating if translation is complete for the current page. Bound to the UI.
    /// 現在のページで翻訳が完了したかどうかを示すフラグ。UIにバインドされます。
    @Published var isTranslationDoneForCurrentPage: Bool = false

    /// A flag to control the visibility of the translation overlay.
    /// 翻訳オーバーレイの表示を制御するためのフラグ。
    @Published var showingOverlay: Bool = false {
        didSet {
            updateOverlay()
        }
    }

    /// Holds the generated image with the translation overlay.
    /// 翻訳オーバーレイ付きで生成された画像を保持します。
    @Published var overlayImage: NSImage? = nil

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
        static let ocrFailureIdentifier = "failure"
        static let failedOCRSamplesDirectory = "failed_ocr_samples"

        // OCR retry logic settings
        static let ocrRetryCropInset: CGFloat = 6.0
        static let ocrInitialNormalization = NormalizationType.scaleTo_0_1
        static let ocrRetryNormalization = NormalizationType.scaleTo_minus1_1
    }

    private static var hasPrintedLanguageModelInstructions = false

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

        // Update the status for the newly set first page.
        // 新しく設定された最初のページのステータスを更新します。
        updatePageStatus()
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
                print("All OCR tasks finished. Setting isExtractionDone to true.")
                page.isExtractionDone = true
                self.saveContext() // This saves the bubbles and the new flag.

                // We are on the main thread, so we can update the UI property.
                // Check if the updated page is still the one being displayed.
                if self.pages.indices.contains(self.currentIndex) &&
                    self.pages[self.currentIndex].sourceURL.lastPathComponent == originalFileName {
                    self.isExtractionDoneForCurrentPage = true
                }
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
    /// To ensure stability, this method now performs only a single OCR attempt using the most stable normalization method.
    /// The retry logic has been removed to prevent a persistent crash (`predictionError`) caused by a state issue in the Core ML model on second use.
    /// 安定性を確保するため、このメソッドは最も安定した正規化手法を用いて単一のOCR試行のみを実行します。
    /// Core MLモデルの2回目の使用時に発生する状態問題による永続的なクラッシュ（`predictionError`）を防ぐため、再試行ロジックは削除されました。
    private func runOCR(on cgImage: CGImage, for bubbleObjectID: NSManagedObjectID, with bubbleID: UUID, completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {

            var ocrResult: (text: String, identifier: String)

            do {
                // Perform OCR, with a single retry for empty results using configured settings.
                // 設定された値を用いて、結果が空の場合に1回だけ再試行します。
                var text = try self.ocrEngine.recognizeText(from: cgImage, normalization: Constants.ocrInitialNormalization)
                var isRetryAttempt = false

                if text.isEmpty {
                    isRetryAttempt = true
                    // The model succeeded but returned no text. Retry once after cropping the image.
                    // モデルは成功したがテキストを返さなかった。画像を切り抜いてから再試行を1回行います。
                    let inset = Constants.ocrRetryCropInset
                    // Ensure the image is large enough to be cropped.
                    // 画像が切り抜けるだけの大きさか確認します。
                    if cgImage.width > Int(inset * 2) && cgImage.height > Int(inset * 2) {
                        let cropRect = CGRect(x: inset,
                                              y: inset,
                                              width: CGFloat(cgImage.width) - inset * 2,
                                              height: CGFloat(cgImage.height) - inset * 2)

                        if let croppedImage = cgImage.cropping(to: cropRect) {
                            // Perform the second OCR attempt on the cropped image.
                            // 切り抜いた画像で2回目のOCRを試みます。
                            text = try self.ocrEngine.recognizeText(from: croppedImage, normalization: Constants.ocrRetryNormalization)
                        }
                    }
                }

                // After all attempts, check if the text is still empty.
                // 全ての試行が終わった後、テキストがまだ空か確認します。
                if isRetryAttempt && text.isEmpty {
                    // If the retry also resulted in an empty string, treat it as a failure.
                    // 再試行でも結果が空文字列だった場合、失敗として扱います。
                    print("OCR returned an empty string on the second attempt for bubble \(bubbleID).")
                    ocrResult = ("", Constants.ocrFailureIdentifier)
                    self.saveFailedOCRImage(cgImage, for: bubbleID)
                } else {
                    // Otherwise, it's a success.
                    // それ以外の場合は成功です。
                    ocrResult = (text, Constants.ocrEngineIdentifier)
                }

            } catch {
                // The OCR attempt itself failed (e.g., predictionError).
                // OCR試行自体が失敗した（例：predictionError）。
                print("OCR failed for bubble \(bubbleID) with error: \(error.localizedDescription)")
                ocrResult = ("[\(error.localizedDescription)]", Constants.ocrFailureIdentifier)
                self.saveFailedOCRImage(cgImage, for: bubbleID)
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

        let isSuccess = result.identifier != Constants.ocrFailureIdentifier

        bubble.ocrText = result.text
        bubble.ocrTimestamp = Date()
        bubble.ocrEngineIdentifier = result.identifier
        bubble.ocrConfidence = isSuccess ? 1.0 : 0.0 // Placeholder confidence / プレースホルダーの信頼度
        bubble.ocrStatus = isSuccess ? "success" : "failure"

        print("OCR Result for bubble [\(bubble.bubbleID!)] with engine [\(result.identifier)]: \(result.text)")
    }

    // MARK: - Text Translation

    /// Translates the text bubbles for the currently displayed image from Japanese to English.
    @available(macOS 14.0, *)
    func translateCurrentImageBubbles() {
        guard currentIndex < pages.count else { return }
        let currentPage = pages[currentIndex]
        let imageURL = currentPage.sourceURL

        Task {
            print("Starting translation for page: \(imageURL.lastPathComponent)")
            
            guard #available(macOS 26.0, *) else {
                print("Fallback on earlier versions")
                return
            }

            let session = TranslationSession(
                installedSource: Locale.Language(identifier: "ja"),
                target: Locale.Language(identifier: "en")
            )
            
            guard let nsImage = await ImageCache.shared.fullImage(for: imageURL),
                  let imageData = nsImage.tiffRepresentation else {
                print("Error: Failed to load image for translation.")
                return
            }
            let imageHash = DataHasher.computeSHA256(for: imageData)

            // 1. Fetch data on the main thread in a non-blocking way
            let bubblesToTranslate = await MainActor.run { () -> [(objectID: NSManagedObjectID, text: String)]? in
                let request: NSFetchRequest<Page> = Page.fetchRequest()
                request.predicate = NSPredicate(format: "fileHash == %@", imageHash)
                guard let page = (try? self.viewContext.fetch(request))?.first,
                      let bubbles = page.bubbles as? Set<BubbleEntity> else {
                    return nil
                }
                return bubbles.compactMap { bubble in
                    guard let text = bubble.ocrText, !text.isEmpty else { return nil }
                    return (objectID: bubble.objectID, text: text)
                }
            }

            guard let bubblesToTranslate = bubblesToTranslate, !bubblesToTranslate.isEmpty else {
                print("No page or bubbles with text found to translate.")
                return
            }

            // 2. Perform async translations on background thread
            var translatedData: [(objectID: NSManagedObjectID, text: String)] = []
            var allSucceeded = true

            for bubbleData in bubblesToTranslate {
                do {
                    let response = try await session.translate(bubbleData.text)
                    translatedData.append((objectID: bubbleData.objectID, text: response.targetText))
                } catch {
                    allSucceeded = false
                    let nsError = error as NSError
                    print("""
                    -----------------------------------------------------------------
                    翻訳エラーが発生しました。
                    テキスト: '\(bubbleData.text)'
                    エラー内容: \(error.localizedDescription)
                    エラードメイン: \(nsError.domain)
                    エラーコード: \(nsError.code)
                    -----------------------------------------------------------------
                    """)
                }
            }

            // 3. Write results back to Core Data on the main thread
            await MainActor.run {
                for data in translatedData {
                    if let bubbleToUpdate = try? self.viewContext.existingObject(with: data.objectID) as? BubbleEntity {
                        bubbleToUpdate.translatedText = data.text
                    }
                }

                if allSucceeded {
                    let request: NSFetchRequest<Page> = Page.fetchRequest()
                    request.predicate = NSPredicate(format: "fileHash == %@", imageHash)
                    if let pageToUpdate = (try? self.viewContext.fetch(request))?.first {
                        pageToUpdate.isTranslationDone = true
                        self.isTranslationDoneForCurrentPage = true
                        print("Setting isTranslationDone to true for page.")
                    }
                } else {
                    print("One or more translations failed. isTranslationDone will not be set.")
                }

                self.saveContext()
                print("Translation finished and context saved.")
            }
        }
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

    // MARK: - Page Status & Overlay Management

    private func updatePageStatus() {
        guard currentIndex < pages.count else {
            isExtractionDoneForCurrentPage = false
            isTranslationDoneForCurrentPage = false
            showingOverlay = false
            return
        }
        let currentPage = pages[currentIndex]
        let imageURL = currentPage.sourceURL

        Task {
            guard let nsImage = await ImageCache.shared.fullImage(for: imageURL),
                  let imageData = nsImage.tiffRepresentation else {
                await MainActor.run {
                    self.isExtractionDoneForCurrentPage = false
                    self.isTranslationDoneForCurrentPage = false
                    self.showingOverlay = false
                }
                return
            }
            let imageHash = DataHasher.computeSHA256(for: imageData)

            let pageStatus = await viewContext.perform {
                let request: NSFetchRequest<Page> = Page.fetchRequest()
                request.predicate = NSPredicate(format: "fileHash == %@", imageHash)
                request.fetchLimit = 1
                guard let page = try? self.viewContext.fetch(request).first else {
                    return (isExtractionDone: false, isTranslationDone: false)
                }
                return (isExtractionDone: page.isExtractionDone, isTranslationDone: page.isTranslationDone)
            }

            await MainActor.run {
                self.isExtractionDoneForCurrentPage = pageStatus.isExtractionDone
                self.isTranslationDoneForCurrentPage = pageStatus.isTranslationDone
                self.showingOverlay = false
            }
        }
    }

    private func updateOverlay() {
        Task {
            if showingOverlay {
                await createOverlayImage()
            } else {
                // Clear the image when not showing the overlay
                await MainActor.run {
                    self.overlayImage = nil
                }
            }
        }
    }

    @MainActor
    private func createOverlayImage() async {
        guard currentIndex < pages.count else { return }
        let currentPage = pages[currentIndex]
        let imageURL = currentPage.sourceURL

        // 1. Load Original Image
        guard let originalImage = await ImageCache.shared.fullImage(for: imageURL),
              let imageData = originalImage.tiffRepresentation else {
            print("Could not load original image for overlay.")
            return
        }
        let imageHash = DataHasher.computeSHA256(for: imageData)

        // 2. Fetch Bubbles from Core Data
        let bubbles: [BubbleEntity] = await viewContext.perform {
            let request: NSFetchRequest<Page> = Page.fetchRequest()
            request.predicate = NSPredicate(format: "fileHash == %@", imageHash)
            guard let page = try? self.viewContext.fetch(request).first,
                  let bubbleSet = page.bubbles as? Set<BubbleEntity> else {
                return []
            }
            return Array(bubbleSet)
        }

        guard !bubbles.isEmpty else {
            print("No bubbles found to draw overlay for.")
            return
        }

        // 3. Render new image
        let newImage = NSImage(size: originalImage.size, flipped: false) { (dstRect) -> Bool in
            // Draw the original image first to act as the background.
            // 背景として機能するように、まず元の画像を描画します。
            originalImage.draw(in: dstRect)

            // To correctly scale the bubble coordinates (which are in pixels) to the drawing context
            // (which is in points), we need to find the relationship between the image's pixel
            // dimensions and its point dimensions.
            // バブルの座標（ピクセル単位）を描画コンテキスト（ポイント単位）に正しくスケーリングするには、
            // 画像のピクセルサイズとポイントサイズの関係を見つける必要があります。
            guard let rep = originalImage.representations.first as? NSBitmapImageRep else {
                print("Error: Could not get NSBitmapImageRep from NSImage to determine pixel size.")
                return false
            }

            let pixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)

            // Avoid division by zero if the image has no pixels.
            // 画像にピクセルがない場合にゼロ除算を回避します。
            guard pixelSize.width > 0, pixelSize.height > 0 else {
                print("Error: Image pixel dimensions are zero.")
                return false
            }

            // Calculate the dynamic scaling factors.
            // 動的なスケーリングファクターを計算します。
            let scaleX = originalImage.size.width / pixelSize.width
            let scaleY = originalImage.size.height / pixelSize.height

            for bubble in bubbles {
                guard let translatedText = bubble.translatedText, !translatedText.isEmpty else { continue }

                // Apply the dynamic scales to the raw pixel coordinates.
                // 動的なスケールを生のピクセル座標に適用します。
                let bubbleRect = CGRect(
                    x: bubble.x * scaleX,
                    y: bubble.y * scaleY,
                    width: bubble.width * scaleX,
                    height: bubble.height * scaleY
                )

                // The drawing handler's context uses a flipped coordinate system (origin at bottom-left).
                // We must convert our top-left based Y-coordinate to this system.
                // 描画ハンドラのコンテキストは反転した座標系（原点が左下）を使用します。
                // 左上基準のY座標をこのシステムに変換する必要があります。
                let flippedY = originalImage.size.height - bubbleRect.origin.y - bubbleRect.size.height
                let finalRect = CGRect(
                    x: bubbleRect.origin.x,
                    y: flippedY,
                    width: bubbleRect.size.width,
                    height: bubbleRect.size.height
                )


                // Fill the bubble's background using the corrected rect.
                // 修正された矩形を使用してフキダシの背景を塗りつぶします。
                NSColor.white.setFill()
                finalRect.fill()

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                paragraphStyle.lineBreakMode = .byWordWrapping

                var fontSize: CGFloat = 40
                var attributes: [NSAttributedString.Key: Any] = [
                    .paragraphStyle: paragraphStyle,
                    .foregroundColor: NSColor.black
                ]

                // Adjust font size to fit bubble
                while fontSize > 6 {
                    let font = NSFont.boldSystemFont(ofSize: fontSize)
                    attributes[.font] = font
                    let constraintRect = CGSize(width: finalRect.width * 0.9, height: .greatestFiniteMagnitude)
                    let boundingBox = translatedText.boundingRect(with: constraintRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)

                    // The font size is acceptable only if the text fits both horizontally and vertically.
                    // テキストが水平方向と垂直方向の両方に収まる場合にのみ、そのフォントサイズは許容されます。
                    if boundingBox.height <= finalRect.height * 0.9 && boundingBox.width <= finalRect.width * 0.9 {
                        break // Font size is good
                    }
                    fontSize -= 2
                }

                let font = NSFont.boldSystemFont(ofSize: fontSize)
                attributes[.font] = font
                let constraintRect = CGSize(width: finalRect.width, height: finalRect.height)
                let finalBoundingBox = translatedText.boundingRect(with: constraintRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)

                // To counteract minor clipping of characters with descenders (like 'g', 'y'),
                // we shift the final text block up slightly. A shift of 10% of the font size
                // is a safe value that shouldn't cause clipping at the top.
                // 'g'や'y'のようなディセンダを持つ文字のわずかなクリッピングを解消するため、
                // 最終的なテキストブロックをわずかに上にシフトします。フォントサイズの10%のシフトは、
                // 上部でのクリッピングを引き起こさない安全な値です。
                let verticalOffset = fontSize * 0.1
                let textRect = CGRect(x: finalRect.origin.x,
                                      y: finalRect.origin.y + (finalRect.height - finalBoundingBox.height) / 2 + verticalOffset,
                                      width: finalRect.width,
                                      height: finalBoundingBox.height)

                translatedText.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
            }
            return true
        }

        // 4. Update the published property
        self.overlayImage = newImage
    }
}
