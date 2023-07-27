import LocalAuthentication

public enum LocalAuth {
    public static var canUseLocalAuth: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    public static func attempt(label: String) async -> Bool? {
        let auth = LAContext()

        if !auth.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            return false
        }

        do {
            return try await auth.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: label)
        } catch {
            return nil
        }
    }
}
