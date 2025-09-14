import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: ImageViewerModel
    
    var body: some View {
        VStack {
            if let image = model.currentImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 600, maxHeight: 600)
            } else {
                Text("画像を読み込んでください")
            }
            
            Button("テスト画像を読み込む") {
                model.loadSampleImage()
            }
        }
        .padding()
    }
}
