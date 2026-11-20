import SwiftUI
struct RecordDetail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let recordID: UUID
    @State private var page = 0
    @State private var editingRecord: SessionRecord?
    @State private var deleting = false
    private var record: SessionRecord? { model.visibleRecords.first { $0.id == recordID } }
    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 12) {
            Picker("详情页面", selection: $page) { Text("战况").tag(0); Text("手账").tag(1) }.pickerStyle(.segmented).padding(.horizontal, 20)
            if let r = record {
                TabView(selection: $page) {
                    VStack(spacing: 12) {
                        HStack { Text(L10n.format("%@记录", r.originLabel)).font(EnchantTheme.title()); Spacer(); Text(r.dayKey).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted) }
                        EnchantCard { HStack { MetricView(title: "活动时长", value: r.formattedDuration); MetricView(title: "次数 · 估算", value: r.origin == .backfill ? "--" : r.cycleEstimate.map(String.init) ?? "--", color: EnchantTheme.magic) }; Text(r.startTimeInSavedZone).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).padding(.top, 8) }
                        EnchantCard { HeartChart(record: r, height: min(140, max(55, geometry.size.height - 420))) }
                        Spacer(minLength: 0)
                        Button("编辑备注") { editingRecord = r }.buttonStyle(EnchantButton(secondary: true))
                    }.padding(.horizontal, 20).padding(.bottom, 16).tag(0)
                    VStack(spacing: 14) {
                        HStack { Illustration(name: "Journal", size: 56); Text("备注").font(EnchantTheme.title()); Spacer() }
                        ScrollView { JournalNoteText(text: r.journalText.isEmpty ? L10n.text("还没有备注") : r.journalText).font(EnchantTheme.body()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.scrollIndicators(.hidden)
                        Button("编辑备注") { editingRecord = r }.buttonStyle(EnchantButton(secondary: true))
                    }.padding(.horizontal, 20).padding(.bottom, 16).tag(1)

                }.tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                Spacer()
                Text("记录已移到回收站").font(EnchantTheme.title()).multilineTextAlignment(.center)
                Button("返回手账") { dismiss() }.buttonStyle(EnchantButton(secondary: true)).padding(20)
                Spacer()
            }
        }.padding(.top, 6)
        }.background(EnchantTheme.background).navigationTitle("记录详情").navigationBarTitleDisplayMode(.inline)
        .task(id: recordID) { if let record { await model.loadHearts(for: record) } }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Button("删除记录", role: .destructive) { deleting = true } } label: { Text("···").font(EnchantTheme.body(24)) }.accessibilityLabel("记录操作") } }
        .sheet(item: $editingRecord) { record in RecordEditor(existing: record) }
        .alert("删除这条记录？", isPresented: $deleting) { Button("取消", role: .cancel) {}; Button("移到回收站", role: .destructive) { model.delete(recordID); if record == nil { dismiss() } } } message: { Text("可在回收站恢复。") }
    }
}
