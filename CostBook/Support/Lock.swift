import SwiftUI
import LocalAuthentication

/// 简单的锁屏状态机：锁住时盖一层毛玻璃 + Face ID
final class Lock: ObservableObject {
    static let shared = Lock()
    @Published var unlocked = false

    func lock() { unlocked = false }

    func unlock() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            unlocked = true // 没有设置密码就放行
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "解锁小账本") { ok, _ in
            DispatchQueue.main.async { if ok { self.unlocked = true } }
        }
    }
}

struct LockScreenModifier: ViewModifier {
    @EnvironmentObject private var lock: Lock
    let enabled: Bool

    func body(content: Content) -> some View {
        ZStack {
            content
            if enabled && !lock.unlocked {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                VStack(spacing: 18) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("小账本已锁定")
                        .font(.headline)
                    Button("解锁") { lock.unlock() }
                        .buttonStyle(.borderedProminent)
                }
                .onAppear { lock.unlock() }
            }
        }
    }
}

extension View {
    func lockScreen(isEnabled: Bool) -> some View {
        modifier(LockScreenModifier(enabled: isEnabled))
            .environmentObject(Lock.shared)
    }
}
