import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    @AppStorage("lockEnabled") private var lockEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ContentView()
        }
        .lockScreen(isEnabled: lockEnabled)
        .onChange(of: scenePhase) { _, phase in
            // 进后台就落锁，回来再验证
            if phase == .background && lockEnabled { Lock.shared.lock() }
        }
    }
}
