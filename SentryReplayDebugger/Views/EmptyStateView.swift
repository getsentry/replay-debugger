import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Load a Replay Session")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 16) {
                Text("To get started, follow these steps:")
                    .font(.headline)
                    .padding(.bottom, 4)

                InstructionStep(
                    number: 1,
                    title: "Open your browser's Developer Tools",
                    detail: "Navigate to the page with the Sentry replay you want to inspect"
                )

                InstructionStep(
                    number: 2,
                    title: "Go to the Network tab",
                    detail: "You may need to reload the page to record network requests"
                )

                InstructionStep(
                    number: 3,
                    title: "Search for \"recording-segment\"",
                    detail: "Filter the network requests to find the replay segment endpoints"
                )

                InstructionStep(
                    number: 4,
                    title: "Copy as cURL",
                    detail: "Right-click any recording-segment request, go to Copy → Copy as cURL"
                )

                VStack(spacing: 8) {
                    Image("DevToolsScreenshot")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    Text("In the Network tab, right-click \"recording-segment\" → Copy → Copy as cURL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)

                InstructionStep(
                    number: 5,
                    title: "Paste in this app",
                    detail: "Use ⌘V or click \"Load JSON\" to paste the cURL command"
                )
            }
            .frame(maxWidth: 700)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InstructionStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    EmptyStateView()
}
