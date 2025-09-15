import SwiftUI

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
}
