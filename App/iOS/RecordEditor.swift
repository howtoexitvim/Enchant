import SwiftUI
private struct EditDraft: Codable, Equatable { var note: String }
struct RecordEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let existing: SessionRecord
    @State private var draft: EditDraft
    @State private var loaded = false
    init(existing: SessionRecord) { self.existing = existing; _draft = State(initialValue: EditDraft(note: existing.journalText)) }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) { Illustration(name: "Journal", size: 40); Text(existing.dayKey).font(EnchantTheme.body()).foregroundStyle(EnchantTheme.muted) }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft.note).font(EnchantTheme.body()).scrollContentBackground(.hidden).padding(12).accessibilityLabel("记录备注")
                    if draft.note.isEmpty {
                        Text("写下备注…").font(EnchantTheme.body()).foregroundStyle(EnchantTheme.muted).padding(.horizontal, 17).padding(.top, 20).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }.background(EnchantTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            }.padding(20).background(EnchantTheme.background).navigationTitle("编辑备注").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存备注") { save() } } }
            .task { if !loaded { if let data = model.readDraft(key: existing.id.uuidString), let cached = try? JSONDecoder().decode(EditDraft.self, from: data) { draft = cached }; loaded = true } }
            .onChange(of: draft) { _, value in if loaded, let data = try? JSONEncoder().encode(value) { model.writeDraft(data, key: existing.id.uuidString) } }
            .alert("保存未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("知道了") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
        }
    }
    private func save() {
        guard var current = model.visibleRecords.first(where: { $0.id == existing.id }) else { model.errorMessage = L10n.text("记录已被删除，草稿已保留。"); return }
        current.note = draft.note; current.links = RecordLink.detected(in: draft.note)
        if model.save(current) { model.removeDraft(key: existing.id.uuidString); dismiss() }
    }
}
