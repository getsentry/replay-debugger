import AuthenticationServices
import SwiftUI

struct WebAuthnBridgeView: NSViewRepresentable {
    let webAuthnData: String
    let onSuccess: (WebAuthnResponse) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSuccess: onSuccess, onError: onError)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchorView = view

        DispatchQueue.main.async {
            self.performAssertion(coordinator: context.coordinator)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func performAssertion(coordinator: Coordinator) {
        guard let cborData = base64urlDecode(webAuthnData) else {
            onError("Invalid base64url challenge data")
            return
        }

        let decoded: CBORValue
        do {
            decoded = try CBORDecoder.decode(cborData)
        } catch {
            onError("Failed to decode challenge: \(error.localizedDescription)")
            return
        }

        guard case .map(let map) = decoded else {
            onError("Expected CBOR map")
            return
        }

        let rpId = map[.text("rpId")]?.textValue ?? "sentry.io"

        guard let challengeValue = map[.text("challenge")] else {
            onError("Missing challenge in data")
            return
        }

        let challengeData: Data
        switch challengeValue {
        case .text(let str):
            guard let d = base64urlDecode(str) else {
                onError("Invalid challenge string")
                return
            }
            challengeData = d
        case .bytes(let d):
            challengeData = d
        default:
            onError("Unexpected challenge type")
            return
        }

        let provider = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let request = provider.createCredentialAssertionRequest(challenge: challengeData)

        if let allowCreds = map[.text("allowCredentials")]?.arrayValue {
            request.allowedCredentials = allowCreds.compactMap { cred in
                guard case .map(let credMap) = cred else { return nil }
                let credId: Data?
                if let idVal = credMap[.text("id")] {
                    switch idVal {
                    case .text(let str): credId = base64urlDecode(str)
                    case .bytes(let d): credId = d
                    default: credId = nil
                    }
                } else {
                    credId = nil
                }
                guard let credId else { return nil }
                return ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(
                    credentialID: credId,
                    transports: ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport.allSupported
                )
            }
        }

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator
        coordinator.retainedController = controller
        controller.performRequests()
    }

    private func base64urlDecode(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }

    class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let onSuccess: (WebAuthnResponse) -> Void
        let onError: (String) -> Void
        weak var anchorView: NSView?
        var retainedController: ASAuthorizationController?

        init(onSuccess: @escaping (WebAuthnResponse) -> Void, onError: @escaping (String) -> Void) {
            self.onSuccess = onSuccess
            self.onError = onError
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            anchorView?.window ?? NSApp.keyWindow ?? NSApp.windows.first!
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            guard let credential = authorization.credential as? ASAuthorizationSecurityKeyPublicKeyCredentialAssertion else {
                onError("Unexpected credential type")
                return
            }

            onSuccess(WebAuthnResponse(
                keyHandle: base64urlEncode(credential.credentialID),
                clientData: base64urlEncode(credential.rawClientDataJSON),
                signatureData: base64urlEncode(credential.signature),
                authenticatorData: base64urlEncode(credential.rawAuthenticatorData)
            ))
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            onError(error.localizedDescription)
        }

        private func base64urlEncode(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
    }
}

// MARK: - Minimal CBOR Decoder

enum CBORValue: Hashable {
    case uint(UInt64)
    case negInt(UInt64)
    case bytes(Data)
    case text(String)
    case array([CBORValue])
    case map([CBORValue: CBORValue])
    case bool(Bool)
    case null

    var textValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    var arrayValue: [CBORValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

enum CBORDecoder {
    enum Error: Swift.Error, LocalizedError {
        case unexpectedEnd
        case unsupportedType(UInt8)

        var errorDescription: String? {
            switch self {
            case .unexpectedEnd: return "Unexpected end of CBOR data"
            case .unsupportedType(let t): return "Unsupported CBOR type: \(t)"
            }
        }
    }

    static func decode(_ data: Data) throws -> CBORValue {
        var offset = 0
        return try decodeItem(data, offset: &offset)
    }

    private static func decodeItem(_ data: Data, offset: inout Int) throws -> CBORValue {
        guard offset < data.count else { throw Error.unexpectedEnd }
        let initial = data[offset]
        offset += 1
        let major = initial >> 5
        let additional = initial & 0x1f

        switch major {
        case 0:
            return .uint(try readLength(additional, data: data, offset: &offset))
        case 1:
            return .negInt(try readLength(additional, data: data, offset: &offset))
        case 2:
            let len = Int(try readLength(additional, data: data, offset: &offset))
            guard offset + len <= data.count else { throw Error.unexpectedEnd }
            let bytes = Data(data[offset..<offset+len])
            offset += len
            return .bytes(bytes)
        case 3:
            let len = Int(try readLength(additional, data: data, offset: &offset))
            guard offset + len <= data.count else { throw Error.unexpectedEnd }
            let str = String(data: Data(data[offset..<offset+len]), encoding: .utf8) ?? ""
            offset += len
            return .text(str)
        case 4:
            let count = Int(try readLength(additional, data: data, offset: &offset))
            var arr: [CBORValue] = []
            for _ in 0..<count { arr.append(try decodeItem(data, offset: &offset)) }
            return .array(arr)
        case 5:
            let count = Int(try readLength(additional, data: data, offset: &offset))
            var map: [CBORValue: CBORValue] = [:]
            for _ in 0..<count {
                let key = try decodeItem(data, offset: &offset)
                map[key] = try decodeItem(data, offset: &offset)
            }
            return .map(map)
        case 7:
            if additional == 20 { return .bool(false) }
            if additional == 21 { return .bool(true) }
            if additional == 22 { return .null }
            throw Error.unsupportedType(initial)
        default:
            throw Error.unsupportedType(initial)
        }
    }

    private static func readLength(_ additional: UInt8, data: Data, offset: inout Int) throws -> UInt64 {
        if additional < 24 { return UInt64(additional) }
        if additional == 24 {
            guard offset < data.count else { throw Error.unexpectedEnd }
            let val = data[offset]; offset += 1; return UInt64(val)
        }
        if additional == 25 {
            guard offset + 2 <= data.count else { throw Error.unexpectedEnd }
            let val = UInt16(data[offset]) << 8 | UInt16(data[offset+1]); offset += 2; return UInt64(val)
        }
        if additional == 26 {
            guard offset + 4 <= data.count else { throw Error.unexpectedEnd }
            let val = UInt32(data[offset]) << 24 | UInt32(data[offset+1]) << 16 | UInt32(data[offset+2]) << 8 | UInt32(data[offset+3])
            offset += 4; return UInt64(val)
        }
        throw Error.unsupportedType(additional)
    }
}
