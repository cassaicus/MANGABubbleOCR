
import SwiftUI
import Vision
import CoreML
import CoreData

class ImageViewerModel: ObservableObject {
    static let shared = ImageViewerModel()
    
    private let viewContext = PersistenceController.shared.container.viewContext

    @Published var pages: [MangaPage] = []
    @Published var currentIndex: Int = 0

    private init() {}

    func setPages(_ newPages: [MangaPage]) {
        self.pages = newPages
        self.currentIndex = 0
        let urls = newPages.map { $0.sourceURL }
        ThumbnailPrefetcher.shared.prefetchThumbnails(for: urls)
    }

    func loadFolder(_ folder: URL) {
        ImageRepository.shared.fetchLocalImagesAsync(from: folder) { [weak self] urls in
            let newPages = urls.map { MangaPage(sourceURL: $0) }
            DispatchQueue.main.async {
                self?.setPages(newPages)
            }
        }
    }

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
                self?.saveBubbles(results, for: imageData, originalFileName: originalFileName, imageSize: CGSize(width: cgImage.width, height: cgImage.height))
            }
            request.imageCropAndScaleOption = .scaleFit
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            try handler.perform([request])
        } catch {
            print("Model loading or inference error: \(error)")
        }
    }
    
    private func saveBubbles(_ results: [VNRecognizedObjectObservation], for imageData: Data, originalFileName: String, imageSize: CGSize) {
        viewContext.perform {
            let hash = DataHasher.computeSHA256(for: imageData)
            let page = self.fetchOrCreatePage(with: hash, originalFileName: originalFileName)
            
            if let existingBubbles = page.bubbles as? NSSet {
                for case let bubble as BubbleEntity in existingBubbles {
                    self.viewContext.delete(bubble)
                }
            }
            
            for observation in results {
                let newBubble = BubbleEntity(context: self.viewContext)
                let rect = observation.boundingBox.toPixelRectFlipped(in: imageSize)
                newBubble.bubbleID = UUID()
                newBubble.x = rect.origin.x
                newBubble.y = rect.origin.y
                newBubble.width = rect.size.width
                newBubble.height = rect.size.height
                newBubble.page = page
            }
            
            do {
                try self.viewContext.save()
                print("Successfully saved bubbles to Core Data.")
            } catch {
                print("Failed to save to Core Data: \(error)")
                self.viewContext.rollback()
            }
        }
    }
    
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
        newPage.pageNumber = 0 // Placeholder
        let book = fetchOrCreateBook()
        newPage.book = book
        return newPage
    }

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
        newBook.folderPath = "" // Placeholder
        return newBook
    }
}


//import SwiftUI
//import Vision
//import CoreML
//
///// アプリケーション全体のUI状態とデータフローを管理する主要なViewModel。
/////
///// このクラスは、表示する漫画のページ(`MangaPage`)のリスト、現在の表示位置などを管理し、
///// SwiftUIビューにUIの変更を通知する役割を担います。
//class ImageViewerModel: ObservableObject {
//    /// アプリケーション全体で共有される唯一のインスタンス（シングルトン）。
//    static let shared = ImageViewerModel()
//
//    /// 表示対象となる漫画の全ページ。@Publishedにより、この配列への変更は自動的にUIに通知されます。
//    @Published var pages: [MangaPage] = []
//
//    /// 現在表示しているページのインデックス。
//    @Published var currentIndex: Int = 0
//
//    /// 外部からの直接的なインスタンス化を防ぐためのプライベートな初期化子。
//    private init() {}
//
//    /// 新しいページのリストでモデルを更新します。
//    /// - Parameter newPages: 表示する新しい`MangaPage`の配列。
//    func setPages(_ newPages: [MangaPage]) {
//        self.pages = newPages
//        self.currentIndex = 0
//
//        // 新しいページのURLリストを取得し、サムネイルのプリフェッチを開始
//        let urls = newPages.map { $0.sourceURL }
//        ThumbnailPrefetcher.shared.prefetchThumbnails(for: urls)
//    }
//
//    /// 指定されたフォルダから画像を非同期で読み込み、ページのリストを更新します。
//    /// - Parameter folder: 画像が含まれるフォルダのURL。
//    func loadFolder(_ folder: URL) {
//        ImageRepository.shared.fetchLocalImagesAsync(from: folder) { [weak self] urls in
//            // URLの配列をMangaPageの配列に変換
//            let newPages = urls.map { MangaPage(sourceURL: $0) }
//
//            DispatchQueue.main.async {
//                self?.setPages(newPages)
//            }
//        }
//    }
//
//    /// フォルダ選択ダイアログを表示し、ユーザーが選択したフォルダから画像を読み込みます。
//    func selectAndLoadFolder() {
//        // 新しいフォルダを選択する前に、進行中のプリフェッチをキャンセル
//        ThumbnailPrefetcher.shared.cancelAll()
//
//        let panel = NSOpenPanel()
//        panel.canChooseDirectories = true
//        panel.canChooseFiles = false
//        panel.allowsMultipleSelection = false
//        if panel.runModal() == .OK, let url = panel.url {
//            loadFolder(url)
//        }
//    }
//
//    // MARK: - Core ML and Vision Integration
//
//    /// 現在表示されている画像からセリフのフキダシを検出し、一時ファイルとして保存します。
//    func analyzeCurrentImageForTextBubbles() {
//        // 現在のページが存在するか確認
//        guard currentIndex < pages.count else {
//            print("現在のページが見つかりません。")
//            return
//        }
//        let currentPage = pages[currentIndex]
//        let imageURL = currentPage.sourceURL
//
//        // isProcessing = true // 処理中のUIフィードバック用フラグ（必要に応じて追加）
//
//        Task {
//            // ImageCacheからフルサイズの画像を非同期で取得
//            guard let nsImage = await ImageCache.shared.fullImage(for: imageURL),
//                  let cgImage = nsImage.cgImage() else {
//                print("画像の読み込みまたはCGImageへの変換に失敗しました。")
//                // isProcessing = false
//                return
//            }
//
//            // Visionリクエストを実行
//            performVisionRequest(with: cgImage)
//        }
//    }
//
//    /// Visionリクエストを実行して、画像内のオブジェクト（フキダシ）を検出します。
//    /// - Parameter cgImage: 分析対象のCGImage。
//    private func performVisionRequest(with cgImage: CGImage) {
//        do {
//            // Core MLモデルのURLを取得
//            guard let modelURL = Bundle.main.url(forResource: "best", withExtension: "mlmodelc") else {
//                print("モデルファイル(best.mlmodelc)が見つかりません。")
//                return
//            }
//
//            // モデルをロードしてVisionリクエストを作成
//            let mlModel = try MLModel(contentsOf: modelURL)
//            let vnModel = try VNCoreMLModel(for: mlModel)
//
//            let request = VNCoreMLRequest(model: vnModel) { [weak self] request, error in
//                if let error = error {
//                    print("Visionリクエストエラー: \(error)")
//                    return
//                }
//
//                guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
//
//                let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
//                var count = 0
//
//                // 結果をループして、検出されたオブジェクトを処理
//                for obs in results {
//                    guard let topLabel = obs.labels.first else { continue }
//
//                    let rect = obs.boundingBox
//                        .toPixelRectFlipped(in: imageSize)
//                        .integralWithin(imageSize: imageSize)
//
//                    if let cropped = cgImage.cropping(to: rect) {
//                        self?.saveCroppedImage(cropped, index: count, label: topLabel.identifier, confidence: topLabel.confidence)
//                        count += 1
//                    }
//                }
//                print("保存されたフキダシの数: \(count)")
//            }
//
//            request.imageCropAndScaleOption = .scaleFit
//
//            // 画像リクエストハンドラを作成して実行
//            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
//            try handler.perform([request])
//
//        } catch {
//            print("モデルの読み込みまたは推論エラー: \(error)")
//        }
//    }
//
//    /// 切り抜いた画像を一時ディレクトリに保存します。
//    /// - Parameters:
//    ///   - cgImage: 保存するCGImage。
//    ///   - index: 画像のインデックス（ファイル名に使用）。
//    ///   - label: 検出されたオブジェクトのラベル。
//    ///   - confidence: 検出の信頼度。
//    private func saveCroppedImage(_ cgImage: CGImage, index: Int, label: String, confidence: Float) {
//        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cropped_bubbles")
//        do {
//            // 一時ディレクトリが存在しない場合は作成
//            if !FileManager.default.fileExists(atPath: tempDir.path) {
//                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
//            }
//
//            let fileName = "cropped_\(index)_\(label)_\(String(format: "%.2f", confidence)).png"
//            let fileURL = tempDir.appendingPathComponent(fileName)
//
//            // 既存のファイルを削除
//            if FileManager.default.fileExists(atPath: fileURL.path) {
//                try FileManager.default.removeItem(at: fileURL)
//            }
//
//            // CGImageをPNGとして保存（VisionExtensions.swiftの拡張機能を使用）
//            try cgImage.save(to: fileURL)
//            print("画像を保存しました: \(fileURL.path)")
//
//        } catch {
//            print("切り抜いた画像の保存に失敗しました: \(error)")
//        }
//    }
//}
