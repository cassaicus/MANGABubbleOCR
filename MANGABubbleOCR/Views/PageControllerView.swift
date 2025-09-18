import SwiftUI

// NSViewControllerRepresentableプロトコルに準拠し、AppKitのNSPageControllerをSwiftUIで利用可能にするためのラッパービュー。
struct PageControllerView: NSViewControllerRepresentable {
    // 監視対象のオブジェクトとしてImageViewerModelのインスタンスを受け取ります。
    // モデルの変更をビューに反映させるために使用します。
    @ObservedObject var model: ImageViewerModel
    
    // SwiftUIビューが作成されるときに呼び出され、NSViewControllerのインスタンスを生成します。
    func makeNSViewController(context: Context) -> PageController {
        // PageControllerのインスタンスを生成します。
        let controller = PageController()
        // 生成したコントローラーにモデルを渡します。
        controller.model = model
        // 設定済みのコントローラーを返します。
        return controller
    }
    
    // SwiftUIビューの状態が更新されたときに呼び出され、NSViewControllerを更新します。
    func updateNSViewController(_ nsViewController: PageController, context: Context) {
        // ビューコントローラーのモデルを最新の状態に更新します。
        nsViewController.model = model
        // ビューコントローラーにデータを再読み込みさせて、表示を更新します。
        nsViewController.reloadData()
    }
}

// MARK: - NSPageController
// NSPageControllerを継承し、ページめくり機能を実装するクラス。
class PageController: NSPageController, NSPageControllerDelegate {
    // 表示する画像のデータを持つImageViewerModel。
    var model: ImageViewerModel?
    private var hasAppeared = false // 一度だけ実行するためのフラグ

    override func viewDidAppear() {
        super.viewDidAppear()

        guard !hasAppeared, let model = model else { return }
        hasAppeared = true

        let currentIndex = model.currentIndex
        let count = model.pages.count

        // 表示中の画像がない場合は何もしません。
        guard count > 0 else { return }

        // NOTE: このメソッドは、ウィンドウのリサイズ時などに`NSPageController`がビューの更新を
        // 正しく反映しないことがある問題への回避策（ワークアラウンド）です。
        // インデックスを意図的に変更して戻すことで、ページの再読み込みを強制します。
        if count == 1 {
            // 画像が1枚しかない場合、他のインデックスに移動できないため、特殊な処理を行います。
            // 一時的に無効なダミーページのリストを設定し、即座に元のページリストに戻すことで、リロードをトリガーします。
            let originalPages = self.arrangedObjects
            let dummyPage = MangaPage(sourceURL: URL(fileURLWithPath: "/dev/null"))
            self.arrangedObjects = [dummyPage]

            // UIの更新が反映されるよう、メインスレッドの次のサイクルで元のリストに戻します。
            DispatchQueue.main.async {
                self.arrangedObjects = originalPages
                self.selectedIndex = 0
            }
            return
        }

        // 画像が複数ある場合は、よりシンプルな方法でリロードをトリガーします。
        // 選択インデックスを一時的に別のインデックスに変更し、すぐに元に戻します。
        // これにより、現在のページの`viewController`が再生成または再設定されることを期待しています。
        let targetIndex = currentIndex == 0 ? 1 : 0 // 現在が0なら1へ、それ以外なら0へ。
        self.selectedIndex = targetIndex
        self.selectedIndex = currentIndex
    }
    
    // ビューコントローラーのビューがメモリに読み込まれた後に呼び出されます。
    override func viewDidLoad() {
        super.viewDidLoad()
        // デリゲートを自身に設定し、ページコントローラーのイベントをハンドリングします。
        delegate = self
        // ページのトランジション（切り替え）スタイルを水平ストリップに設定します。
        transitionStyle = .horizontalStrip
        // 表示するオブジェクトの配列をモデルのページ配列に設定します。
        arrangedObjects = model?.pages ?? []
        // 初期表示されるページのインデックスをモデルの現在のインデックスに設定します。
        selectedIndex = model?.currentIndex ?? 0
    }
    
    // 外部からデータを再読み込みするために呼び出されるメソッド。
    func reloadData() {
        // 表示するオブジェクトの配列を最新のページ配列に更新します。
        arrangedObjects = model?.pages ?? []
        // 表示ページのインデックスを最新の現在のインデックスに更新します。
        selectedIndex = model?.currentIndex ?? 0
    }
    
    // 指定されたIDに対応するビューコントローラーを返すデリゲートメソッド。
    func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: String) -> NSViewController {
        // 新しいImagePageViewControllerのインスタンスを生成して返します。
        return ImagePageViewController()
    }
    
    // 指定されたオブジェクトに対応するIDを返すデリゲートメソッド。
    func pageController(_ pageController: NSPageController, identifierFor object: Any) -> String {
        // すべてのページで共通のID "ImagePage" を返します。
        return "ImagePage"
    }
    
    // ビューコントローラーが表示される直前に呼び出され、ビューコントローラーの準備を行うデリゲートメソッド。
    func pageController(_ pageController: NSPageController, prepare viewController: NSViewController, with object: Any?) {
        // viewControllerをImagePageViewControllerに、objectをMangaPageにキャストできるか確認します。
        guard let vc = viewController as? ImagePageViewController,
              let page = object as? MangaPage else { return }
        // キャストが成功した場合、ビューコントローラーに表示する画像のURLを設定します。
        vc.imageURL = page.sourceURL
    }
    
    // ページのトランジションアニメーションが完了した後に呼び出されるデリゲートメソッド。
    func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
        // モデルの現在のインデックスを選択されているページのインデックスに更新します。
        model?.currentIndex = selectedIndex
        // トランジションを完了させます。
        completeTransition()
    }
}

// MARK: - 画像表示用VC
// 1枚の画像を非同期に表示するためのNSViewController。
class ImagePageViewController: NSViewController {
    // 表示する画像のURL。
    var imageURL: URL? {
        didSet {
            // URLが設定されたら、ビューを更新する必要があるか確認します。
            if isViewLoaded, let url = imageURL {
                updateView(with: url)
            }
        }
    }
    
    private var hostingController: NSHostingController<AnyView>?

    // このビューコントローラーのビューを生成または読み込むために呼び出されます。
    override func loadView() {
        // 初期ビューとして空のNSViewを設定します。
        self.view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let url = imageURL {
            updateView(with: url)
        }
    }
    
    private func updateView(with url: URL) {
        // 既存のホスティングコントローラーがあれば削除
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        // AsyncFullImageViewをホストする新しいNSHostingControllerを作成
        // ここで .ignoresSafeArea() を追加して、タイトルバー領域にも表示されるようにする
        let newHostingController = NSHostingController(rootView: AnyView(AsyncFullImageView(url: url).ignoresSafeArea()))

        addChild(newHostingController)
        newHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(newHostingController.view)
        self.hostingController = newHostingController

        // Auto Layout を使って、ホスティングビューが親ビュー全体を埋めるように制約を設定
        NSLayoutConstraint.activate([
            newHostingController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            newHostingController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            newHostingController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            newHostingController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }
}
