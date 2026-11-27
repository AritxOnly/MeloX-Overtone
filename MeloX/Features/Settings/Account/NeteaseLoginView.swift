import CoreImage.CIFilterBuiltins
import SwiftUI
import WebKit

struct NeteaseLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(NeteaseAPI.self) private var api
    @State private var attempt = 0
    @State private var image: CGImage?
    @State private var status: LocalizedStringKey = "ui.watch.qr.generating"
    @State private var canRetry = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 1, orientation: .up)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .padding(24)
                            .background(.white, in: .rect(cornerRadius: 20))
                            .accessibilityLabel("ui.watch.qr.accessibility")
                    } else if canRetry {
                        Image(systemName: "qrcode").font(.largeTitle).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 248, height: 248)
                Text(status).font(.headline)
                if canRetry {
                    Button("ui.watch.qr.regenerate") { attempt += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text("ui.account.qr.instructions")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("ui.watch.qr.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("ui.common.cancel", role: .cancel) { dismiss() }
            }
        }
        .task(id: attempt) { await signIn() }
    }

    private func signIn() async {
        image = nil
        canRetry = false
        status = "ui.watch.qr.generating"
        do {
            let challenge = try await api.loginQRCodeURL()
            try Task.checkCancellation()
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(challenge.url.absoluteString.utf8)
            filter.correctionLevel = "M"
            guard let code = filter.outputImage,
                  let rendered = CIContext().createCGImage(code, from: code.extent) else {
                throw APIError.invalidResponse
            }
            image = rendered
            status = "ui.watch.qr.waiting_scan"
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(2))
                guard UIApplication.shared.applicationState == .active else { continue }
                let state = try await api.qrLoginStatus(key: challenge.key)
                try Task.checkCancellation()
                switch state {
                case .waiting: status = "ui.watch.qr.waiting_scan"
                case .scanned: status = "ui.account.qr.confirm"
                case .expired:
                    image = nil
                    status = "ui.account.qr.expired"
                    canRetry = true
                    return
                case .authorized(let cookie):
                    settings.cookie = cookie
                    dismiss()
                    return
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            status = image == nil ? "ui.watch.qr.generation_failed" : "ui.watch.qr.status_check_failed"
            image = nil
            canRetry = true
        }
    }
}

// Clear cookies left by installations that used web sign-in before upgrading.
@MainActor
enum NeteaseWebCookieStore {
    private static let dataStore = WKWebsiteDataStore.default()

    static func clear() async {
        for cookie in await allCookies() where isNeteaseCookie(cookie) {
            await dataStore.httpCookieStore.deleteCookie(cookie)
        }
    }

    private static func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private static func isNeteaseCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return domain == "163.com" || domain.hasSuffix(".163.com")
    }
}
