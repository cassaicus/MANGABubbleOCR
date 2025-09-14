import SwiftUI

struct ContentView: View {
    @ObservedObject private var model = ImageViewerModel.shared

    var body: some View {
        VStack {
            PageControllerView(model: model, holder: model.repository)
                .frame(minWidth: 600, minHeight: 400)

            HStack {
                Button("画像を追加") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        for url in panel.urls {
                            model.addImage(url: url)
                        }
                    }
                }
                Button("現在の画像を削除") {
                    model.removeCurrentImage()
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
