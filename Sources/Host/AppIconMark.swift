import SwiftUI

/// Dock-style mark (padded squircle + loupe). Asset is `QLMark`.
struct AppIconMark: View {
    var body: some View {
        Image("QLMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
    }
}
