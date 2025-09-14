import SwiftUI
import AppKit

struct PageControllerView: NSViewRepresentable {
    @ObservedObject var model: ImageViewerModel
    @ObservedObject var holder: ImageRepository

    func makeNSView(context: Context) -> NSView {
        let pageController = NSPageController()
        pageController.delegate = context.coordinator
        pageController.transitionStyle = .horizontalStrip
        pageController.view.wantsLayer = true
        context.coordinator.pageController = pageController
        return pageController.view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let pageController = context.coordinator.pageController else { return }
        let images = holder.images

        // 常に1件以上ある前提（ダミー含む）
        pageController.arrangedObjects = images
        let safeIndex = min(model.currentIndex, images.count - 1)
        pageController.selectedIndex = safeIndex
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSPageControllerDelegate {
        var parent: PageControllerView
        var pageController: NSPageController?

        init(_ parent: PageControllerView) {
            self.parent = parent
        }

        func pageController(_ pageController: NSPageController,
                            viewControllerFor object: Any) -> NSViewController {
            guard let url = object as? URL else {
                return NSViewController()
            }

            // ダミーURLは空ビュー
            if url.path == "/dev/null" {
                let vc = NSViewController()
                vc.view = NSView()
                vc.view.wantsLayer = true
                vc.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                return vc
            }

            guard let image = NSImage(contentsOf: url) else {
                return NSViewController()
            }

            let imageView = NSImageView(image: image)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false

            let vc = NSViewController()
            vc.view = NSView()
            vc.view.addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: vc.view.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor)
            ])

            return vc
        }

        func pageController(_ pageController: NSPageController,
                            identifierFor object: Any) -> NSPageController.ObjectIdentifier {
            if let url = object as? URL {
                return url.absoluteString
            }
            return UUID().uuidString
        }

        func pageController(_ pageController: NSPageController,
                            didTransitionTo object: Any) {
            if let idx = pageController.arrangedObjects.firstIndex(where: { $0 as AnyObject === object as AnyObject }) {
                parent.model.currentIndex = idx
            }
        }
    }
}
