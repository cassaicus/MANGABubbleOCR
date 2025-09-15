import SwiftUI

// アプリケーションのメインコンテンツを表示するビュー構造体。
struct ContentView: View {
    // 環境オブジェクトとして注入されたImageViewerModelのインスタンスにアクセスします。
    // このビューやサブビューでモデルのデータを共有します。
    @EnvironmentObject var model: ImageViewerModel
    // サムネイル表示と1枚表示を切り替えるための状態を管理するプロパティ。
    // @Stateプロパティラッパーにより、この値が変更されるとビューが再描画されます。
    @State private var showThumbnails = false
    
    // ビューの本体を定義します。
    var body: some View {
        // ZStackを使用して、ビューを重ねて表示します。
        ZStack {
            // 背景を黒色に設定し、セーフエリアを無視して全画面に広げます。
            Color.black.ignoresSafeArea()
            
            // 表示するページがまだ読み込まれていない場合の処理。
            if model.pages.isEmpty {
                // ユーザーにフォルダ選択を促すテキストを表示します。
                Text("フォルダを選んで jpg を読み込んでください")
                    .foregroundColor(.white) // テキストの色を白に設定します。
                    .padding() // テキストの周りに余白を追加します。
            } else {
                // showThumbnailsがtrueの場合の処理。
                if showThumbnails {
                    // サムネイルの一覧をスクロール表示します。
                    ScrollView {
                        // LazyVGridを使用して、5列のグリッドレイアウトを作成します。
                        LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 10), count: 5), spacing: 10) {
                            // ページのインデックスをループ処理します。
                            ForEach(model.pages.indices, id: \.self) { index in
                                // ボタンとして画像を表示します。
                                Button(action: {
                                    // ボタンがタップされたら、モデルの現在のインデックスを更新します。
                                    model.currentIndex = index
                                    // 1枚表示モードに切り替えます。
                                    showThumbnails = false
                                }) {
                                    // AsyncImageViewを使用してサムネイルを非同期に読み込み、表示します。
                                    AsyncImageView(url: model.pages[index].sourceURL, maxSize: 200)
                                        .frame(height: 200) // 高さを200ポイントに固定します。
                                        .clipped() // フレーム外にはみ出した部分を切り取ります。
                                        .overlay(
                                             // 現在選択中の画像に青い枠を表示します。
                                             RoundedRectangle(cornerRadius: 4)
                                                 .stroke(Color.blue, lineWidth: 4)
                                                 .opacity(index == model.currentIndex ? 1 : 0)
                                         )
                                }
                                // ボタンのスタイルを、装飾のないシンプルなものに設定します。
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding() // グリッドの周りに余白を追加します。
                    }
                } else {
                    // 1枚の画像をスライド表示するためのビュー。
                    PageControllerView(model: model)
                        .ignoresSafeArea() // セーフエリアを無視して全画面に広げます。
                }
            }
            
            // UIコントロール（ボタンなど）を配置するためのVStack。
            VStack {
                // 上部にスペーサーを配置し、コントロールを画面下部に押しやります。
                Spacer()
                // ボタンを水平に並べるためのHStack。
                HStack {
                    // 左側にスペーサーを配置し、ボタンを右寄せにします。
                    Spacer()
                    
                    VStack{
                        // ページが読み込まれている場合のみ、サムネイルボタンを表示します。
                        if !model.pages.isEmpty {
                            // サムネイル表示と1枚表示を切り替えるためのボタン。
                            Button(showThumbnails ? "1枚表示" : "サムネイル") {
                                // ボタンがタップされたらshowThumbnailsの値を反転させます。
                                showThumbnails.toggle()
                            }
                            .padding(8) // ボタンの周りに8ポイントの余白を追加します。
                            .background(.ultraThinMaterial) // 半透明の背景効果を適用します。
                            .clipShape(RoundedRectangle(cornerRadius: 8)) // 角を丸くします。
                        }

                        // フォルダを選択するためのボタン。
                        Button("フォルダを選択") {
                            // ボタンがタップされたらモデルのメソッドを呼び出します。
                            model.selectAndLoadFolder()
                        }
                        .padding(8) // ボタンの周りに8ポイントの余白を追加します。
                        .background(.ultraThinMaterial) // 半透明の背景効果を適用します。
                        .clipShape(RoundedRectangle(cornerRadius: 8)) // 角を丸くします。
                    }
                }
                .padding() // HStackの周りに余白を追加します。
            }
        }
    }
}
