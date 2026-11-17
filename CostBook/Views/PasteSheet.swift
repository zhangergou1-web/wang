import SwiftUI

/// 粘贴 CSV 的独立页面。
/// 用 UITextView 而非 SwiftUI TextEditor：几千行的 CSV 用 TextEditor 会卡死。
struct PasteSheet: View {
    @Binding var text: String
    var onParse: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if text.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("把 CSV 内容粘贴到这里")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TextView(text: $text)
                }
            }
            .navigationTitle(text.isEmpty ? "粘贴 CSV 文本" : "已粘贴 \(text.count) 字符")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        if let s = UIPasteboard.general.string { text = s }
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                    Spacer()
                    Button {
                        onParse()
                        dismiss()
                    } label: {
                        Text("解析").bold()
                    }
                    .disabled(text.isEmpty)
                }
            }
        }
    }
}

/// 轻量 UITextView 封装，支持大段文本不卡顿
struct TextView: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.autocapitalizationType = .none
        tv.autocorrectionType = .no
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        tv.text = text
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textViewDidChange(_ tv: UITextView) {
            text.wrappedValue = tv.text
        }
    }
}
