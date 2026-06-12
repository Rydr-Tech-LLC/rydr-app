import SwiftUI

struct SplashCoordinatorView: View {
    @State private var showMainApp = false

    var body: some View {
        Group {
            if showMainApp {
                DriverLoginView()
            } else {
                SplashVideoView {
                    withAnimation {
                        showMainApp = true
                    }
                }
            }
        }
    }
}
