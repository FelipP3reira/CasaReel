import FeatureWalk3D
import SwiftUI

/// Hosts the Walk 3D flow; the model lives in `RootView` so work continues across navigation.
struct Walk3DScreen: View {
    @Environment(Walk3DModel.self) private var model

    var body: some View {
        Walk3DView(model: model)
            .navigationTitle(Text("Walk 3D"))
            .navigationBarTitleDisplayMode(.inline)
    }
}
