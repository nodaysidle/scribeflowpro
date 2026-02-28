import SwiftUI

/// Displays text token-by-token from an AsyncStream, auto-scrolling as tokens arrive.
struct StreamingTextView: View {
    let stream: AsyncStream<String>
    let onComplete: ((String) -> Void)?

    @State private var text = ""
    @State private var isStreaming = false

    init(stream: AsyncStream<String>, onComplete: ((String) -> Void)? = nil) {
        self.stream = stream
        self.onComplete = onComplete
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text + (isStreaming ? "▊" : ""))
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .id("streamingText")
            }
            .onChange(of: text) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("streamingText", anchor: .bottom)
                }
            }
        }
        .task {
            isStreaming = true
            for await token in stream {
                text += token
            }
            isStreaming = false
            onComplete?(text)
        }
    }
}
