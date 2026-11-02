import LocalAuthentication
import SwiftUI

/// Asks for Face ID, Touch ID or the device passcode before DueDay's bills can be seen.
/// It locks each time the app goes to the background.
@MainActor
@Observable
final class AppLock {
    static let enabledKey = "appLockEnabled"

    /// True while the lock screen is up.
    private(set) var isLocked: Bool
    /// Changes every time the app locks. Giving the content a new identity closes any sheet that was
    /// open, so it can't stay on screen above the lock.
    private(set) var generation = 0
    private var isAuthenticating = false
    /// The system prompt briefly makes the app inactive, so without this a cancelled prompt would
    /// bring the app back to active and ask again, forever. The prompt comes up by itself once per
    /// lock. After that the Unlock button asks again.
    private var autoPromptPending: Bool

    init() {
        isLocked = Self.isEnabled
        autoPromptPending = Self.isEnabled
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// False when the device has no passcode set, since there'd be nothing to unlock with.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lockIfNeeded() {
        guard Self.isEnabled, !isLocked else { return }
        isLocked = true
        autoPromptPending = true
        generation += 1
    }

    /// Shows the system prompt. Stays locked if the person cancels or fails. With `automatic`, it
    /// only asks if it hasn't already for this lock.
    func unlock(automatic: Bool = false) async {
        guard isLocked, !isAuthenticating else { return }
        if automatic {
            guard autoPromptPending else { return }
            autoPromptPending = false
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        if await Self.authenticate(reason: "Unlock DueDay") {
            isLocked = false
        }
    }

    /// Face ID or Touch ID, falling back to the passcode.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Covers the app while it's locked, and hides it in the app switcher.
struct LockCover: View {
    let lock: AppLock

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if lock.isLocked {
                VStack(spacing: 18) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accent)
                    Text("DueDay is locked")
                        .font(.outfit(20, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Button("Unlock") {
                        Task { await lock.unlock() }
                    }
                    .font(.outfit(17, weight: .semibold))
                }
            }
        }
    }
}
