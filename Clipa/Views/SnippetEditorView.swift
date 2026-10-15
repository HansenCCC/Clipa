import SwiftUI

/// 集合片段编辑器：新建 / 编辑提示词等（标题可选 + 多行正文）。
struct SnippetEditorView: View {
    let item: ClipItem?
    var onSave: (String, String) -> Void
    var onCancel: () -> Void

    @State private var title: String
    @State private var text: String

    init(item: ClipItem?, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.item = item
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: item?.title ?? "")
        _text = State(initialValue: item?.plainText ?? "")
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(item == nil ? "New Snippet" : "Edit Snippet").font(Theme.Font.headline)

            TextField("Title (optional)", text: $title).textFieldStyle(.roundedBorder)

            Text("Content").font(Theme.Font.caption).foregroundStyle(Theme.Color.secondary)
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ClipaColor.cardBorder, lineWidth: 1))

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(title, text) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 460, height: 420)
    }
}
