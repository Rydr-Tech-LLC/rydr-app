import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Security
import UIKit

struct DriverSocialAuthProfile {
    let firstName: String
    let lastName: String
    let displayName: String
    let email: String
    let providerID: String
}

enum DriverSocialAuthService {
    static func signInWithGoogle(completion: @escaping (Result<(AuthCredential, DriverSocialAuthProfile), Error>) -> Void) {
        guard FirebaseApp.app()?.options.clientID != nil else {
            completion(.failure(NSError(domain: "DriverSocialAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase client ID for Google sign-in."])))
            return
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? windowScene.windows.first?.rootViewController else {
            completion(.failure(NSError(domain: "DriverSocialAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to open Google sign-in."])))
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let googleUser = result?.user,
                  let idToken = googleUser.idToken?.tokenString else {
                completion(.failure(NSError(domain: "DriverSocialAuth", code: -3, userInfo: [NSLocalizedDescriptionKey: "Google sign-in did not return a valid token."])))
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: googleUser.accessToken.tokenString
            )
            let profile = googleProfile(from: googleUser)
            completion(.success((credential, profile)))
        }
    }

    static func credential(from authorization: ASAuthorization, nonce: String) -> Result<(AuthCredential, DriverSocialAuthProfile), Error> {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            return .failure(NSError(domain: "DriverSocialAuth", code: -4, userInfo: [NSLocalizedDescriptionKey: "Apple sign-in did not return a valid token."]))
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )
        let profile = DriverSocialAuthProfile(
            firstName: appleIDCredential.fullName?.givenName ?? "",
            lastName: appleIDCredential.fullName?.familyName ?? "",
            displayName: PersonNameComponentsFormatter().string(from: appleIDCredential.fullName ?? PersonNameComponents()),
            email: appleIDCredential.email ?? "",
            providerID: "apple.com"
        )
        return .success((credential, profile))
    }

    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < UInt8(charset.count) {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }

    private static func googleProfile(from user: GIDGoogleUser) -> DriverSocialAuthProfile {
        let givenName = user.profile?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let familyName = user.profile?.familyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = user.profile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let splitName = splitDisplayName(displayName)
        return DriverSocialAuthProfile(
            firstName: givenName.isEmpty ? splitName.first : givenName,
            lastName: familyName.isEmpty ? splitName.last : familyName,
            displayName: displayName,
            email: user.profile?.email ?? "",
            providerID: GoogleAuthProviderID
        )
    }

    private static func splitDisplayName(_ displayName: String) -> (first: String, last: String) {
        let parts = displayName.split(separator: " ").map(String.init)
        guard let first = parts.first else { return ("", "") }
        return (first, parts.dropFirst().joined(separator: " "))
    }
}
