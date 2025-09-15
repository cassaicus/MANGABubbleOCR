import Foundation

/// サムネイルのプリフェッチ（先読み）を管理するシングルトンサービス。
///
/// ネットワークから画像を非同期にダウンロードし、サムネイルを生成してキャッシュに保存する処理を
/// バックグラウンドで実行します。これにより、ユーザーがサムネイルを表示する前にキャッシュが準備され、
/// 表示パフォーマンスが向上します。
final class ThumbnailPrefetcher {
    /// アプリケーション全体で共有される唯一のインスタンス。
    static let shared = ThumbnailPrefetcher()

    /// プリフェッチ処理の状態をスレッドセーフに管理するためのアクター。
    private let prefetchActor = PrefetchActor()

    /// シングルトンパターンを強制するため、`init`をプライベートに宣言します。
    private init() {}

    /// 指定されたURLリストに対してサムネイルのプリフェッチを開始します。
    /// - Parameter urls: プリフェッチ対象の画像URLの配列。
    func prefetchThumbnails(for urls: [URL]) {
        Task {
            await prefetchActor.add(urls: urls)
        }
    }

    /// 現在のプリフェッチタスクをすべてキャンセルします。
    func cancelAll() {
        Task {
            await prefetchActor.cancelAll()
        }
    }

    /// プリフェッチ処理の状態を管理するアクター。
    ///
    /// 内部でキューを持ち、指定された数のタスクを並行して実行します。
    actor PrefetchActor {
        /// プリフェッチ待ちのURLキュー。
        private var queue: [URL] = []
        /// 現在実行中のタスクのセット。
        private var runningTasks: Set<Task<Void, Never>> = []
        /// 最大同時実行数。
        private let maxConcurrentTasks = 5

        /// URLをプリフェッチキューに追加し、処理を開始します。
        /// - Parameter urls: 追加するURLの配列。
        func add(urls: [URL]) {
            // 重複を避けつつキューに追加
            let newUrls = urls.filter { !queue.contains($0) }
            self.queue.append(contentsOf: newUrls)
            processQueue()
        }

        /// すべての待機中および実行中のタスクをキャンセルします。
        func cancelAll() {
            // キューを空にする
            queue.removeAll()
            // 実行中のタスクをすべてキャンセル
            runningTasks.forEach { $0.cancel() }
            runningTasks.removeAll()
        }

        /// キューからURLを取り出してプリフェッチ処理を実行します。
        private func processQueue() {
            // 実行中のタスクが最大数に達しているか、キューが空の場合は何もしない
            while runningTasks.count < maxConcurrentTasks, !queue.isEmpty {
                let url = queue.removeFirst()

                let task = Task {
                    // すでにキャッシュに存在するか確認（サムネイル用のキーで）
                    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                    components.queryItems = [URLQueryItem(name: "thumbnail_size", value: "\(200)")]
                    let thumbKey = components.url!

                    if ImageCache.shared.image(for: thumbKey) == nil {
                        // キャッシュになければ生成
                        _ = await ImageCache.shared.thumbnail(for: url, maxSize: 200)
                    }
                }

                // タスクが完了したら`runningTasks`から自身を削除するように後処理を仕込む
                let completionTask = Task {
                    await task.value
                    // タスク完了後に自身をリストから削除し、次の処理を開始
                    runningTasks.remove(task)
                    processQueue()
                }
                runningTasks.insert(completionTask)
            }
        }
    }
}
