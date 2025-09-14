import SwiftUI

struct PageControllerView: NSViewControllerRepresentable {
    @ObservedObject var model: ImageViewerModel
    
    func makeNSViewController(context: Context) -> PageController {
        let controller = PageController()
        controller.model = model
        return controller
    }
    
    func updateNSViewController(_ nsViewController: PageController, context: Context) {
        nsViewController.model = model
        nsViewController.reloadData()
    }
}

// MARK: - NSPageController
class PageController: NSPageController, NSPageControllerDelegate {
    var model: ImageViewerModel?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        transitionStyle = .horizontalStrip
        arrangedObjects = model?.images ?? []
        selectedIndex = model?.currentIndex ?? 0
    }
    
    func reloadData() {
        arrangedObjects = model?.images ?? []
        selectedIndex = model?.currentIndex ?? 0
    }
    
    func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: String) -> NSViewController {
        return ImagePageViewController()
    }
    
    func pageController(_ pageController: NSPageController, identifierFor object: Any) -> String {
        return "ImagePage"
    }
    
    func pageController(_ pageController: NSPageController, prepare viewController: NSViewController, with object: Any?) {
        guard let vc = viewController as? ImagePageViewController,
              let url = object as? URL else { return }
        vc.image = NSImage(contentsOf: url)
    }
    
    func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
        model?.currentIndex = selectedIndex
        completeTransition()
    }
}

// MARK: - 画像表示用VC
class ImagePageViewController: NSViewController {
    var image: NSImage?
    private var imageView: NSImageView!
    
    override func loadView() {
        imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.black.cgColor
        self.view = imageView
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        imageView.image = image
    }
}
