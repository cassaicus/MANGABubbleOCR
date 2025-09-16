import SwiftUI
import Vision
import CoreML
import CoreData

/// `ImageViewerModel`は、アプリケーションのUI状態とデータフローを管理する主要なViewModelです。
///
/// このクラスは、表示する漫画のページ(`MangaPage`)のリスト、現在の表示インデックス、
/// およびCore Dataとのやり取りを管理します。UIの変更をトリガーするために`@Published`プロパティを使用し、
/// SwiftUIビューに更新を通知します。このクラスはシングルトンとして実装されており、
/// アプリケーション全体で単一のインスタンスが共有されます。
class ImageViewerModel: ObservableObject {
    /// アプリケーション全体で共有される`ImageViewerModel`のシングルトンインスタンス。
    static let shared = ImageViewerModel()
    
    /// Core Dataの永続化コントローラから取得した、メインスレッド用の`NSManagedObjectContext`。
    /// データベース操作はすべてこのコンテキストを介して行われます。
    private let viewContext = PersistenceController.shared.container.viewContext

    /// 表示対象となる漫画の全ページを保持する配列。
    /// `@Published`ラッパーにより、このプロパティへの変更は自動的に関連するSwiftUIビューに通知され、UIが更新されます。
    @Published var pages: [MangaPage] = []

    /// `pages`配列内で現在表示されているページのインデックス。
    /// この値が変更されると、表示される画像も更新されます。
    @Published var currentIndex: Int = 0

    /// OCRエンジンへの参照。
    private let ocrEngine: OCREngine?

    /// シングルトンパターンを強制するため、初期化子をプライベートに設定します。
    /// 外部からの直接的なインスタンス化を防ぎます。
    private init() {
        // OCRエンジンを初期化します。失敗した場合はnilが設定されます。
        self.ocrEngine = OCREngine()
        if ocrEngine == nil {
            print("ImageViewerModel: OCREngineの初期化に失敗しました。")
        }
    }

    /// 新しいページのリストでモデルを更新します。
    ///
    /// 既存のページリストを新しいもので置き換え、現在のインデックスをリセットします。
    /// また、新しいページのサムネイルをバックグラウンドでプリフェッチするように`ThumbnailPrefetcher`に指示します。
    /// - Parameter newPages: 表示する新しい`MangaPage`の配列。
    func setPages(_ newPages: [MangaPage]) {
        self.pages = newPages
        self.currentIndex = 0
        let urls = newPages.map { $0.sourceURL }
        ThumbnailPrefetcher.shared.prefetchThumbnails(for: urls)
    }

    /// 指定されたフォルダから画像を非同期で読み込み、ページのリストを更新します。
    ///
    /// `ImageRepository`を使用して指定されたフォルダ内の画像URLを取得し、
    /// それらを`MangaPage`オブジェクトに変換して、メインスレッドでUIを更新します。
    /// - Parameter folder: 画像ファイルが含まれるフォルダのURL。
    func loadFolder(_ folder: URL) {
        ImageRepository.shared.fetchLocalImagesAsync(from: folder) { [weak self] urls in
            let newPages = urls.map { MangaPage(sourceURL: $0) }
            DispatchQueue.main.async {
                self?.setPages(newPages)
            }
        }
    }

    /// フォルダ選択ダイアログを表示し、ユーザーが選択したフォルダから画像を読み込みます。
    ///
    /// `NSOpenPanel`を使用してユーザーにフォルダを選択させ、選択が完了したら
    /// `loadFolder`メソッドを呼び出して画像の読み込みを開始します。
    /// フォルダ選択前には、進行中のサムネイルプリフェッチ処理をすべてキャンセルします。
    func selectAndLoadFolder() {
        ThumbnailPrefetcher.shared.cancelAll()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            loadFolder(url)
        }
    }

    /// 現在表示されている画像からフキダシ（テキストバブル）を検出します。
    ///
    /// このメソッドは、現在のページの画像を非同期で取得し、Visionフレームワークと
    /// Core MLモデルを使用してフキダシの位置を検出する一連の処理を開始します。
    func analyzeCurrentImageForTextBubbles() {
        guard currentIndex < pages.count else { return }
        let currentPage = pages[currentIndex]
        let imageURL = currentPage.sourceURL

        Task {
            guard let nsImage = await ImageCache.shared.fullImage(for: imageURL),
                  let cgImage = nsImage.cgImage(),
                  let imageData = nsImage.tiffRepresentation else {
                print("Failed to load image or convert to data.")
                return
            }
            performVisionRequest(with: cgImage, imageData: imageData, originalFileName: imageURL.lastPathComponent)
        }
    }

    /// Visionリクエストを実行して、画像内のフキダシを検出します。
    ///
    /// 指定された`CGImage`に対して、事前に訓練されたCore MLモデル（`best.mlmodelc`）を
    /// 使った`VNCoreMLRequest`を作成し、実行します。検出結果は`saveBubbles`メソッドに渡されます。
    /// - Parameters:
    ///   - cgImage: 分析対象のCGImage。
    ///   - imageData: Core Dataに保存するための元の画像データ。
    ///   - originalFileName: 元のファイル名。
    private func performVisionRequest(with cgImage: CGImage, imageData: Data, originalFileName: String) {
        do {
            guard let modelURL = Bundle.main.url(forResource: "best", withExtension: "mlmodelc") else {
                print("Model file not found.")
                return
            }
            let mlModel = try MLModel(contentsOf: modelURL)
            let vnModel = try VNCoreMLModel(for: mlModel)
            let request = VNCoreMLRequest(model: vnModel) { [weak self] request, error in
                if let error = error {
                    print("Vision request error: \(error)")
                    return
                }
                guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
                // cgImageを渡すように変更
                self?.saveBubbles(results, for: imageData, originalFileName: originalFileName, cgImage: cgImage)
            }
            request.imageCropAndScaleOption = .scaleFit
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            try handler.perform([request])
        } catch {
            print("Model loading or inference error: \(error)")
        }
    }
    
    private let ocrEngineIdentifier = "MangaOCR-v1.0"

    /// 検出されたフキダシの情報をCore Dataに保存し、切り抜いた画像を一時フォルダに保存します。
    ///
    /// このメソッドは、まず画像データのハッシュを計算して、対応する`Page`エンティティを検索または作成します。
    /// 既存のフキダシ情報を削除した後、新しい検出結果を`BubbleEntity`として保存します。
    /// 同時に、各フキダシの領域を`cgImage`から切り出し、一時ディレクトリにPNGファイルとして保存し、OCRを実行します。
    /// すべてのOCRタスクが完了した後に、一度だけCore Dataコンテキストを保存します。
    /// - Parameters:
    ///   - results: Visionリクエストから得られた検出結果の配列。
    ///   - imageData: ハッシュ計算とページ識別のための画像データ。
    ///   - originalFileName: ページの元のファイル名。
    ///   - cgImage: 切り出し元のCGImage。
    private func saveBubbles(_ results: [VNRecognizedObjectObservation], for imageData: Data, originalFileName: String, cgImage: CGImage) {
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let ocrDispatchGroup = DispatchGroup()

        // 切り抜いた画像を保存する一時ディレクトリを作成
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cropped_bubbles")
        do {
            if !FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            print("Failed to create temporary directory: \(error)")
            return
        }

        viewContext.perform {
            let hash = DataHasher.computeSHA256(for: imageData)
            let page = self.fetchOrCreatePage(with: hash, originalFileName: originalFileName)
            
            // 既存のフキダシを削除
            if let existingBubbles = page.bubbles as? NSSet {
                for case let bubble as BubbleEntity in existingBubbles {
                    self.viewContext.delete(bubble)
                }
            }
            
            // 新しいフキダシを保存し、画像を切り抜く
            for observation in results {
                let newBubble = BubbleEntity(context: self.viewContext)
                let rect = observation.boundingBox.toPixelRectFlipped(in: imageSize)

                newBubble.bubbleID = UUID()
                newBubble.x = rect.origin.x
                newBubble.y = rect.origin.y
                newBubble.width = rect.size.width
                newBubble.height = rect.size.height
                newBubble.page = page

                // OCR関連のデフォルト値を設定
                newBubble.shouldOcr = true // デフォルトでOCR対象とする
                newBubble.ocrStatus = "pending"

                // 画像を切り出して保存し、OCRを実行
                if newBubble.shouldOcr, let croppedCGImage = cgImage.cropping(to: rect) {
                    let fileName = "\(newBubble.bubbleID!).png"
                    let fileURL = tempDir.appendingPathComponent(fileName)
                    do {
                        try croppedCGImage.save(to: fileURL)

                        // OCR実行
                        ocrDispatchGroup.enter()
                        self.runOCR(on: croppedCGImage, for: newBubble.objectID) {
                            ocrDispatchGroup.leave()
                        }

                    } catch {
                        print("Failed to save cropped image: \(error)")
                        newBubble.ocrStatus = "failure"
                    }
                } else {
                    newBubble.ocrStatus = "skipped"
                }
            }
            
            // すべてのOCRタスクが完了した後にコンテキストを保存
            ocrDispatchGroup.notify(queue: .main) {
                do {
                    if self.viewContext.hasChanges {
                        try self.viewContext.save()
                        print("Successfully saved bubbles and OCR results to Core Data.")
                    }
                } catch {
                    print("Failed to save to Core Data: \(error)")
                    self.viewContext.rollback()
                }
            }
        }
    }
    
    /// 指定されたハッシュ値を持つ`Page`エンティティをCore Dataから取得または新規作成します。
    ///
    /// - Parameters:
    ///   - hash: 検索または作成のキーとなる画像データのSHA-256ハッシュ。
    ///   - originalFileName: 新規作成時に使用する元のファイル名。
    /// - Returns: 既存の、または新しく作成された`Page`エンティティ。
    private func fetchOrCreatePage(with hash: String, originalFileName: String) -> Page {
        let request: NSFetchRequest<Page> = Page.fetchRequest()
        request.predicate = NSPredicate(format: "fileHash == %@", hash)
        
        do {
            let results = try viewContext.fetch(request)
            if let existingPage = results.first {
                return existingPage
            }
        } catch {
            print("Failed to fetch page: \(error)")
        }
        
        let newPage = Page(context: viewContext)
        newPage.pageID = UUID()
        newPage.fileHash = hash
        newPage.originalFileName = originalFileName
        newPage.pageNumber = 0 // プレースホルダー
        let book = fetchOrCreateBook()
        newPage.book = book
        return newPage
    }

    /// `Book`エンティティをCore Dataから取得または新規作成します。
    ///
    /// 現在の実装では、最初の`Book`エンティティを取得するか、存在しない場合は
    /// "Default Book"というタイトルの新しい`Book`を作成します。
    /// - Returns: 既存の、または新しく作成された`Book`エンティティ。
    private func fetchOrCreateBook() -> Book {
        let request: NSFetchRequest<Book> = Book.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let results = try viewContext.fetch(request)
            if let existingBook = results.first {
                return existingBook
            }
        } catch {
            print("Failed to fetch book: \(error)")
        }
        
        let newBook = Book(context: viewContext)
        newBook.bookID = UUID()
        newBook.title = "Default Book"
        newBook.folderPath = "" // プレースホルダー
        return newBook
    }

    /// 指定された画像に対してOCRを実行し、結果をCore Dataに保存します。
    /// 失敗した場合は、異なる正規化方法で再試行します。
    /// - Parameters:
    ///   - cgImage: OCRを実行する画像。
    ///   - bubbleObjectID: 結果を保存するBubbleEntityのNSManagedObjectID。
    ///   - completion: 処理完了時に呼び出されるクロージャ。
    private func runOCR(on cgImage: CGImage, for bubbleObjectID: NSManagedObjectID, completion: @escaping () -> Void) {
        guard let engine = self.ocrEngine else {
            print("OCR for \(bubbleObjectID): Engine not available.")
            viewContext.perform {
                if let bubble = try? self.viewContext.existingObject(with: bubbleObjectID) as? BubbleEntity {
                    bubble.ocrStatus = "failure"
                    bubble.ocrText = "Engine not available"
                }
                completion()
            }
            return
        }

        // OCR処理は重い可能性があるため、バックグラウンドスレッドで実行
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. 最初の試行 (改良版スケール)
            var resultText = engine.recognizeText(from: cgImage, normalization: .scaleTo_minus1_1)
            var finalIdentifier = self.ocrEngineIdentifier

            // 2. 失敗した場合、2回目の試行 (オリジナル版スケール)
            if resultText.starts(with: "[OCR Error:") {
                print("OCR failed with default normalization, retrying with alternate...")
                resultText = engine.recognizeText(from: cgImage, normalization: .scaleTo_0_1)
                finalIdentifier = "MangaOCR-v1.0-kai" // 2回目であることを示すIDに変更
            }

            // 3. Core Dataの更新は、そのコンテキストのキューで行う
            self.viewContext.perform {
                guard let bubble = try? self.viewContext.existingObject(with: bubbleObjectID) as? BubbleEntity else {
                    completion()
                    return
                }

                // OCR結果を保存
                bubble.ocrText = resultText
                bubble.ocrTimestamp = Date()
                bubble.ocrEngineIdentifier = finalIdentifier
                bubble.ocrConfidence = resultText.starts(with: "[OCR Error:") ? 0.0 : 1.0
                bubble.ocrStatus = resultText.starts(with: "[OCR Error:") ? "failure" : "success"

                print("Final OCR Result for bubble [\(bubble.bubbleID!)] with engine [\(finalIdentifier)]: \(resultText)")

                // 処理完了を通知
                completion()
            }
        }
    }
}
