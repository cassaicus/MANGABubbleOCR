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
            
            // 表示する画像がまだ読み込まれていない場合の処理。
            if model.images.isEmpty {
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
                            // 画像のインデックスをループ処理します。
                            ForEach(model.images.indices, id: \.self) { index in
                                // ボタンとして画像を表示します。
                                Button(action: {
                                    // ボタンがタップされたら、モデルの現在のインデックスを更新します。
                                    model.currentIndex = index
                                    // 1枚表示モードに切り替えます。
                                    showThumbnails = false
                                }) {
                                    // AsyncImageViewを使用してサムネイルを非同期に読み込み、表示します。
                                    AsyncImageView(url: model.images[index])
                                        .frame(height: 200) // 高さを200ポイントに固定します。
                                        .clipped() // フレーム外にはみ出した部分を切り取ります。
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
                        // 画像が読み込まれている場合のみ、サムネイルボタンを表示します。
                        if !model.images.isEmpty {
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
                            // ボタンがタップされたらopenFolder()メソッドを呼び出します。
                            openFolder()
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
    
    // フォルダ選択パネルを開き、選択されたフォルダから画像を読み込むプライベートメソッド。
    private func openFolder() {
        // NSOpenPanelのインスタンスを作成します。
        let panel = NSOpenPanel()
        // ディレクトリの選択を許可します。
        panel.canChooseDirectories = true
        // ファイルの選択を禁止します。
        panel.canChooseFiles = false
        // 複数選択を禁止します。
        panel.allowsMultipleSelection = false
        // パネルをモーダルで表示し、ユーザーが「OK」をクリックした場合の処理。
        if panel.runModal() == .OK {
            // 選択されたフォルダのURLが正常に取得できた場合の処理。
            if let url = panel.url {
                // ImageRepositoryを使用して、選択されたフォルダから画像を取得します。
//                let images = ImageRepository.shared.fetchLocalImages(from: url)
//                // 取得した画像リストをモデルに設定します。
//                model.setImages(images)
                model.loadFolder(url)
            }
        }
    }
}
