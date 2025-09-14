import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: ImageViewerModel
    @State private var showThumbnails = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if model.images.isEmpty {
                Text("フォルダを選んで jpg を読み込んでください")
                    .foregroundColor(.white)
                    .padding()
            } else {
                if showThumbnails {
                    // サムネイル一覧
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 10), count: 5), spacing: 10) {
                            ForEach(model.images.indices, id: \.self) { index in
                                if let image = NSImage(contentsOf: model.images[index]) {
                                    Button(action: {
                                        model.currentIndex = index
                                        showThumbnails = false
                                    }) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(height: 120)
                                            .clipped()
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    // 1枚スライド表示
                    PageControllerView(model: model)
                        .ignoresSafeArea()
                }
            }
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    // フォルダ選択ボタン
                    Button("フォルダを選択") {
                        openFolder()
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // サムネイル切替ボタン
                    Button(showThumbnails ? "1枚表示" : "サムネイル") {
                        showThumbnails.toggle()
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }
        }
    }
    
    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            if let url = panel.url {
                let images = ImageRepository.shared.fetchLocalImages(from: url)
                model.setImages(images)
            }
        }
    }
}
