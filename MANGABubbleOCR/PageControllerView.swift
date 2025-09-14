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
    
    // ビューコントローラーのビューがメモリに読み込まれた後に呼び出されます。
    override func viewDidLoad() {
        super.viewDidLoad()
        // デリゲートを自身に設定し、ページコントローラーのイベントをハンドリングします。
        delegate = self
        // ページのトランジション（切り替え）スタイルを水平ストリップに設定します。
        transitionStyle = .horizontalStrip
        // 表示するオブジェクトの配列をモデルの画像URL配列に設定します。モデルがnilの場合は空配列を設定します。
        arrangedObjects = model?.images ?? []
        // 初期表示されるページのインデックスをモデルの現在のインデックスに設定します。
        selectedIndex = model?.currentIndex ?? 0
    }
    
    // 外部からデータを再読み込みするために呼び出されるメソッド。
    func reloadData() {
        // 表示するオブジェクトの配列を最新の画像URL配列に更新します。
        arrangedObjects = model?.images ?? []
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
        // viewControllerをImagePageViewControllerに、objectをURLにキャストできるか確認します。
        guard let vc = viewController as? ImagePageViewController,
              let url = object as? URL else { return }
        // キャストが成功した場合、ビューコントローラーに表示する画像（NSImage）を設定します。
        vc.image = NSImage(contentsOf: url)
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
// 1枚の画像を表示するためのNSViewController。
class ImagePageViewController: NSViewController {
    // 表示するNSImage。
    var image: NSImage?
    // 画像を表示するためのNSImageView。
    private var imageView: NSImageView!
    
    // このビューコントローラーのビューを生成または読み込むために呼び出されます。
    override func loadView() {
        // NSImageViewのインスタンスを生成します。
        imageView = NSImageView()
        // 画像のスケーリング方法を、アスペクト比を維持して拡大・縮小するように設定します。
        imageView.imageScaling = .scaleProportionallyUpOrDown
        // 画像の配置を中央に設定します。
        imageView.imageAlignment = .alignCenter
        // レイヤーバックのビューを有効にします。Core Animationの機能を利用するために必要です。
        imageView.wantsLayer = true
        // ビューの背景色を黒に設定します。
        imageView.layer?.backgroundColor = NSColor.black.cgColor
        // このビューコントローラーのメインビューとしてimageViewを設定します。
        self.view = imageView
    }
    
    // ビューが画面に表示される直前に呼び出されます。
    override func viewWillAppear() {
        super.viewWillAppear()
        // imageViewに表示する画像を設定します。
        imageView.image = image
    }
}
