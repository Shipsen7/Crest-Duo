import SwiftUI

/// The fork's app mark. The internal type name is retained for upstream merges.
struct CrestStartPageMark: View {
    // MARK: - Variables

    var body: some View {
        Image("FennavioPreview")
            .resizable()
            .scaledToFit()
    }
}

#if DEBUG
    #Preview("Component") {
        CrestStartPageMark().frame(width: 80, height: 80).padding()
    }
#endif
