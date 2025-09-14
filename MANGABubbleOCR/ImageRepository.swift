import Foundation

// このクラスは、画像ファイルの入出力（IO）を担当します。
// ファイルシステムから画像を読み込む機能を提供します。
class ImageRepository {
    // ImageRepositoryの唯一のインスタンスを生成し、どこからでもアクセスできるようにします（シングルトンパターン）。
    static let shared = ImageRepository()
    // 外部からのインスタンス化を防ぐために、initをprivateに設定します。
    private init() {}
    
    // 指定されたフォルダから、ローカルに保存されている画像ファイルのURLリストを取得します。
    func fetchLocalImages(from folder: URL) -> [URL] {
        // ファイル操作を行うためのFileManagerのデフォルトインスタンスを取得します。
        let fm = FileManager.default
        // 指定されたフォルダ内のすべてのアイテムのURLを取得します。
        // エラーが発生した場合は、空の配列を返します。
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        // 取得したアイテムをフィルタリングおよびソートします。
        return items
            // 拡張子が "jpg" または "jpeg" のファイルのみを抽出します（大文字小文字を区別しません）。
            .filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            // ファイル名で昇順にソートします。
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
