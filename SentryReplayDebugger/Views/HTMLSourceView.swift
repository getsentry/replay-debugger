import SwiftUI
import AppKit

struct HTMLSourceView: View {
    let html: String
    @Binding var searchQuery: String
    @State private var currentMatchIndex: Int = 0
    @State private var totalMatches: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search HTML...", text: $searchQuery)
                    .textFieldStyle(.plain)

                if !searchQuery.isEmpty {
                    Text("\(currentMatchIndex > 0 ? currentMatchIndex : 0) of \(totalMatches)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(action: previousMatch) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(totalMatches == 0)

                    Button(action: nextMatch) {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(totalMatches == 0)

                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            AttributedTextView(
                html: html,
                searchQuery: $searchQuery,
                currentMatchIndex: $currentMatchIndex,
                totalMatches: $totalMatches
            )
        }
    }

    private func nextMatch() {
        if totalMatches > 0 {
            currentMatchIndex = (currentMatchIndex % totalMatches) + 1
        }
    }

    private func previousMatch() {
        if totalMatches > 0 {
            currentMatchIndex = currentMatchIndex > 1 ? currentMatchIndex - 1 : totalMatches
        }
    }
}

struct AttributedTextView: NSViewRepresentable {
    let html: String
    @Binding var searchQuery: String
    @Binding var currentMatchIndex: Int
    @Binding var totalMatches: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        // Beautify and highlight the HTML
        let beautifiedHTML = HTMLBeautifier.beautify(html)
        let attributed = HTMLSyntaxHighlighter.highlight(beautifiedHTML)

        textView.textStorage?.setAttributedString(attributed)

        // Apply search highlighting if there's a search query
        if !searchQuery.isEmpty {
            let matches = findMatches(in: beautifiedHTML, query: searchQuery)
            DispatchQueue.main.async {
                self.totalMatches = matches.count
                if matches.isEmpty {
                    self.currentMatchIndex = 0
                } else if self.currentMatchIndex == 0 {
                    self.currentMatchIndex = 1
                } else if self.currentMatchIndex > matches.count {
                    self.currentMatchIndex = matches.count
                }
            }

            // Highlight all matches
            for (index, range) in matches.enumerated() {
                let isCurrentMatch = (index + 1) == currentMatchIndex
                let backgroundColor = isCurrentMatch ? NSColor.systemYellow : NSColor.systemYellow.withAlphaComponent(0.3)
                textView.textStorage?.addAttribute(.backgroundColor, value: backgroundColor, range: range)
            }

            // Scroll to current match
            if currentMatchIndex > 0 && currentMatchIndex <= matches.count {
                let matchRange = matches[currentMatchIndex - 1]
                textView.scrollRangeToVisible(matchRange)
                textView.showFindIndicator(for: matchRange)
            }
        } else {
            DispatchQueue.main.async {
                self.totalMatches = 0
                self.currentMatchIndex = 0
            }
        }
    }

    private func findMatches(in text: String, query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }

        var ranges: [NSRange] = []
        let nsString = text as NSString
        let options: NSString.CompareOptions = [.caseInsensitive]

        var searchRange = NSRange(location: 0, length: nsString.length)

        while searchRange.location < nsString.length {
            let foundRange = nsString.range(of: query, options: options, range: searchRange)
            if foundRange.location != NSNotFound {
                ranges.append(foundRange)
                searchRange.location = foundRange.location + foundRange.length
                searchRange.length = nsString.length - searchRange.location
            } else {
                break
            }
        }

        return ranges
    }
}

struct HTMLSyntaxHighlighter {
    static func highlight(_ html: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: html)

        // Define colors
        let tagColor = NSColor.systemBlue
        let attributeNameColor = NSColor.systemPurple
        let attributeValueColor = NSColor.systemGreen
        let textColor = NSColor.labelColor
        let commentColor = NSColor.systemGray

        // Set base font and color
        let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        attributed.addAttribute(.font, value: baseFont, range: NSRange(location: 0, length: attributed.length))
        attributed.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: attributed.length))

        let htmlString = html as NSString

        // Highlight comments
        let commentPattern = "<!--[\\s\\S]*?-->"
        if let commentRegex = try? NSRegularExpression(pattern: commentPattern, options: []) {
            let matches = commentRegex.matches(in: html, options: [], range: NSRange(location: 0, length: htmlString.length))
            for match in matches {
                attributed.addAttribute(.foregroundColor, value: commentColor, range: match.range)
            }
        }

        // Highlight DOCTYPE
        let doctypePattern = "<!DOCTYPE[^>]*>"
        if let doctypeRegex = try? NSRegularExpression(pattern: doctypePattern, options: [.caseInsensitive]) {
            let matches = doctypeRegex.matches(in: html, options: [], range: NSRange(location: 0, length: htmlString.length))
            for match in matches {
                attributed.addAttribute(.foregroundColor, value: tagColor, range: match.range)
            }
        }

        // Highlight tags and attributes
        let tagPattern = "</?[a-zA-Z][^>]*>"
        if let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: []) {
            let matches = tagRegex.matches(in: html, options: [], range: NSRange(location: 0, length: htmlString.length))

            for match in matches {
                let tagRange = match.range
                let tagString = htmlString.substring(with: tagRange)

                // Highlight the whole tag structure (< and >)
                attributed.addAttribute(.foregroundColor, value: tagColor, range: tagRange)

                // Highlight attributes within the tag
                let attributePattern = "\\s([a-zA-Z-]+)\\s*=\\s*\"([^\"]*)\""
                if let attrRegex = try? NSRegularExpression(pattern: attributePattern, options: []) {
                    let attrMatches = attrRegex.matches(in: tagString, options: [], range: NSRange(location: 0, length: tagString.count))

                    for attrMatch in attrMatches {
                        // Attribute name
                        if attrMatch.numberOfRanges > 1 {
                            let nameRange = attrMatch.range(at: 1)
                            let absoluteNameRange = NSRange(location: tagRange.location + nameRange.location, length: nameRange.length)
                            attributed.addAttribute(.foregroundColor, value: attributeNameColor, range: absoluteNameRange)
                        }

                        // Attribute value
                        if attrMatch.numberOfRanges > 2 {
                            let valueRange = attrMatch.range(at: 2)
                            let absoluteValueRange = NSRange(location: tagRange.location + valueRange.location, length: valueRange.length)
                            attributed.addAttribute(.foregroundColor, value: attributeValueColor, range: absoluteValueRange)
                        }
                    }
                }
            }
        }

        return attributed
    }
}
