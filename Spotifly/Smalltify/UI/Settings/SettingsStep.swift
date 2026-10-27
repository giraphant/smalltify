import SwiftUI

struct SettingsStep<Content: View>: View {
    let number: Int
    let title: String
    let status: SettingsStatus
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(number, format: .number)
                    .font(.caption).bold()
                    .frame(width: 22, height: 22)
                    .background(status.color.opacity(0.18), in: .circle)
                    .foregroundStyle(status.color)
                Text(title).font(.headline)
                Spacer()
                Text(status.title).font(.callout).foregroundStyle(status.color)
            }
            content()
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5), lineWidth: 0.5) }
    }
}

extension SettingsStatus {
    var color: Color {
        switch tone {
        case .neutral: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

struct SettingsMessage: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.red.opacity(0.1), in: .rect(cornerRadius: 8))
            .textSelection(.enabled)
    }
}
