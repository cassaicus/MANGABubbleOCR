//このコントローラでimagePathsを管理します
//imagePathsへの操作は全てこのクラスを通るようにします。
//

import SwiftUI

class ImagePathsController: ObservableObject {
    
    var imagePaths  =  ["a.jpg", "b.jpg", "c.jpg", "d.jpg"]
    
}
