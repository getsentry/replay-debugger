import SwiftUI

struct UserAvatarView: View {
    let profile: UserProfile?
    var size: CGFloat = 28

    @State private var nsImage: NSImage?

    private var cornerRadius: CGFloat { size / 2 }

    var body: some View {
        Group {
            if let rounded = nsImage?.rounded(size: size, cornerRadius: cornerRadius) {
                Image(nsImage: rounded)
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: size, height: size)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                .frame(width: size, height: size)
        }
        .task(id: profile?.avatarURL) {
            guard let url = profile?.avatarURL else {
                nsImage = nil
                return
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                nsImage = NSImage(data: data)
            } catch {
                nsImage = nil
            }
        }
    }
}

private extension NSImage {
    func rounded(size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        let targetSize = NSSize(width: size, height: size)
        let result = NSImage(size: targetSize)
        result.lockFocus()
        let path = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: targetSize),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        path.addClip()
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1.0
        )
        result.unlockFocus()
        return result
    }
}
