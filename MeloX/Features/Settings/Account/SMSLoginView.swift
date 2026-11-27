import SwiftUI

struct SMSLoginFields {
    var country = "86"
    var phone = ""
    var code = ""
    var resendAfter = Date.distantPast

    var hasValidNumber: Bool {
        guard (1...3).contains(country.count), country.first != "0",
              country.allSatisfy({ "0123456789".contains($0) }),
              phone.allSatisfy({ "0123456789".contains($0) }) else { return false }
        return country == "86" ? phone.count == 11 : (4...(15 - country.count)).contains(phone.count)
    }
}

struct SMSLoginView: View {
    private enum Request { case send, signIn }
    @Binding var fields: SMSLoginFields
    @Environment(\.dismiss) private var dismiss
    @Environment(NeteaseAPI.self) private var api
    @Environment(AppSettings.self) private var settings
    @State private var request: Request?
    @State private var message: String?
    @FocusState private var enteringCode: Bool

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("+").foregroundStyle(.secondary)
                    TextField("ui.account.sms.country", text: $fields.country)
                        .keyboardType(.numberPad)
                        .frame(width: 44)
                        .accessibilityLabel("ui.account.sms.country")
                    Divider()
                    TextField("ui.account.sms.phone", text: $fields.phone)
                        .keyboardType(.numberPad)
                        .textContentType(.telephoneNumber)
                }
                HStack {
                    TextField("ui.account.sms.code", text: $fields.code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($enteringCode)
                    TimelineView(.periodic(from: .now, by: 1)) { clock in
                        let remaining = max(0, Int(ceil(fields.resendAfter.timeIntervalSince(clock.date))))
                        Button {
                            request = .send
                        } label: {
                            if remaining > 0 {
                                Text(L10n.format("ui.account.sms.resend", remaining))
                                    .monospacedDigit()
                            } else {
                                Text("ui.account.sms.send")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(!fields.hasValidNumber || remaining > 0 || request != nil)
                    }
                }
            } footer: {
                if let message { Text(message) }
            }
            .disabled(request != nil)

            Section {
                Button("ui.settings.account.login") { request = .signIn }
                    .frame(maxWidth: .infinity)
                    .disabled(!fields.hasValidNumber || !(4...8).contains(fields.code.count)
                        || !fields.code.allSatisfy { "0123456789".contains($0) } || request != nil)
            } footer: {
                Text("ui.account.sms.alternatives")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: fields.phone) { fields.code = ""; message = nil }
        .onChange(of: fields.country) { fields.code = ""; message = nil }
        .task(id: request) {
            guard let request else { return }
            message = nil
            do {
                switch request {
                case .send:
                    try await api.sendLoginCode(phone: fields.phone, countryCode: fields.country)
                    try Task.checkCancellation()
                    fields.resendAfter = Date().addingTimeInterval(60)
                    message = L10n.string("ui.account.sms.sent")
                    enteringCode = true
                case .signIn:
                    let header = try await api.signIn(phone: fields.phone, countryCode: fields.country, code: fields.code)
                    try Task.checkCancellation()
                    settings.cookie = header
                    dismiss()
                }
            } catch {
                guard !Task.isCancelled else { return }
                if case APIError.server(_, let reason) = error, !reason.isEmpty, reason.count < 200 {
                    message = reason
                } else {
                    message = error.localizedDescription
                }
            }
            self.request = nil
        }
    }
}
