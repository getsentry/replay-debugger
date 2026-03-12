import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("No Replay Loaded")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Paste a Sentry replay URL or replay JSON to get started.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Image(systemName: "command")
                    .font(.system(size: 12, weight: .medium))
                Text("V")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .foregroundColor(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView()
}
