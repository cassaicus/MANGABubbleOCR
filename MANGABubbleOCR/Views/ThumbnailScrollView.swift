import SwiftUI

struct ThumbnailScrollView: View {
    @EnvironmentObject var model: ImageViewerModel
    @Binding var showThumbnails: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(model.pages.indices, id: \.self) { index in
                        Button(action: {
                            model.currentIndex = index
                            showThumbnails = false
                        }) {
                            AsyncImageView(url: model.pages[index].sourceURL, maxSize: 200)
                                .frame(height: 200)
                                .clipped()
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.blue, lineWidth: 4)
                                        .opacity(index == model.currentIndex ? 1 : 0)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id(index) // Add an ID for scrolling
                    }
                }
                .padding()
            }
            .onAppear {
                // Scroll to the current index when the view appears
                proxy.scrollTo(model.currentIndex, anchor: .center)
            }
        }
    }
}
