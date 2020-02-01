//
//  LocalAuth.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 28/09/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import LocalAuthentication

final class LocalAuth {
    static var canUseLocalAuth: Bool {
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static func attempt(label: String, completion: @escaping (Bool) -> Void) {
        let auth = LAContext()
        if !auth.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            completion(false)
            return
        }
        
        auth.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: label) { success, error in
            if (error as NSError?)?.code == -2 { return } // cancelled
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}
