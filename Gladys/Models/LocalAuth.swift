import LocalAuthentication

final class LocalAuth {
    static var canUseLocalAuth: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static func attempt(label: String, completion: @escaping (Bool) -> Void) {
        let auth = LAContext()
        if !auth.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            completion(false)
            return
        }

        auth.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: label) { success, error in
            if (error as NSError?)?.code == -2 { return } // cancelled
            Task { @MainActor in
                completion(success)
            }
        }
    }
}
