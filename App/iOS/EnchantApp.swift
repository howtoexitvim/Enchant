import SwiftUI
import UIKit

@main struct EnchantApp: App {
    @StateObject private var model = AppModel()
    init() {
        let font = UIFont(name: "Fusion-Pixel-12px-Prop-zh-Hans-Regular", size: 18) ?? .systemFont(ofSize: 18)
        UINavigationBar.appearance().titleTextAttributes = [.font: font, .foregroundColor: UIColor(EnchantTheme.ink)]
        let tabFont = UIFont(name: "Fusion-Pixel-12px-Prop-zh-Hans-Regular", size: 12) ?? .systemFont(ofSize: 12)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabFont], for: .normal)
    }
    var body: some Scene { WindowGroup { PhoneRoot().environmentObject(model).preferredColorScheme(.dark).tint(EnchantTheme.accent).font(EnchantTheme.body()) } }
}
struct PhoneRoot: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) var phase
    @State private var sessionPresented = false
    @State private var selectedTab = 0
    var body: some View {
        Group {
            if let message = model.loadError {
                VStack(spacing: 20) { Illustration(name: "Journal"); Text("资料库需要处理").font(EnchantTheme.title()); Text(message); Button("保留原文件并新建资料库") { model.createFreshStorePreservingOriginal() }.buttonStyle(EnchantButton()) }.padding().background(EnchantTheme.background)
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack { PhoneHome(openJournal: { selectedTab = 1 }) }.tabItem { Label { Text("附魔") } icon: { Image("SwordIcon").renderingMode(.original) } }.tag(0)
                    NavigationStack { JournalView() }.tabItem { Label { Text("手账") } icon: { Image("JournalIcon").renderingMode(.original) } }.tag(1)
                    NavigationStack { SettingsView() }.tabItem { Label { Text("设置") } icon: { Image("SettingsIcon").renderingMode(.original) } }.tag(2)
                }.background(EnchantTheme.background)
            }
        }
        .fullScreenCover(isPresented: $sessionPresented) { SessionFlow().environmentObject(model).preferredColorScheme(.dark).tint(EnchantTheme.accent).font(EnchantTheme.body()) }
        .onAppear { model.sceneChanged(phase); sessionPresented = model.active != nil || model.result != nil }
        .onChange(of: model.active?.id) { _, id in if id != nil { sessionPresented = true } }
        .onChange(of: phase) { _, value in model.sceneChanged(value) }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil && !sessionPresented }, set: { if !$0 { model.errorMessage = nil } })) { Button("知道了") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
        .privacySensitive()
    }
}
struct PhoneHome: View {
    @EnvironmentObject var model: AppModel
    let openJournal: () -> Void
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                HStack { VStack(alignment: .leading, spacing: 6) { Text("ENCHANT").font(EnchantTheme.digits(24)).foregroundStyle(EnchantTheme.accent); Text("只属于你的附魔时刻").font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted) }; Spacer(); PixelIcon(name: "spark", color: EnchantTheme.magic, size: 24) }
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    Illustration(name: "PlainSword", size: min(160, geometry.size.height * 0.24))
                    Text("每一个开始，都值得收藏。").font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                    Button { model.start() } label: { HStack { PixelIcon(name: "play", color: EnchantTheme.background); Text("附魔开始") } }.buttonStyle(EnchantButton()).accessibilityLabel("附魔开始").accessibilityIdentifier("start-enchantment")
                    HStack(spacing: 12) {
                        homeMetric(title: "本月记录", value: "\(monthRecords.count)", color: EnchantTheme.accent)
                        homeMetric(title: "本月活动时长", value: SessionRecord.durationString(monthRecords.reduce(0) { $0 + $1.activeDuration(at: $1.endedAt ?? $1.lastCheckpoint) }), color: EnchantTheme.magic)
                    }
                }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(EnchantTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(EnchantTheme.border.opacity(0.5)))
                    .padding(.bottom, geometry.size.height < 600 ? 12 : 24)
                Button(action: openJournal) {
                    HStack(spacing: 12) {
                        Illustration(name: "Journal", size: 48)
                        VStack(spacing: 6) {
                            Text("魔法手账").font(EnchantTheme.title())
                            Text(L10n.format("%ld 条收藏", model.visibleRecords.count)).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted)
                        }.multilineTextAlignment(.center)
                    }.padding(.horizontal, 24).frame(maxWidth: .infinity, alignment: .center).frame(minHeight: 76)
                        .overlay(alignment: .trailing) { Text("›").foregroundStyle(EnchantTheme.accent).padding(.trailing, 14).accessibilityHidden(true) }
                        .background(EnchantTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityLabel("魔法手账")
                Text(model.connectivity.status).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
            }.padding(20).frame(width: geometry.size.width, height: geometry.size.height)
        }.background(EnchantTheme.background).navigationTitle("附魔").navigationBarTitleDisplayMode(.inline)
    }
    private func homeMetric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value).font(EnchantTheme.digits(22)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(L10n.text(title)).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).lineLimit(1).minimumScaleFactor(0.85)
        }.frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
    }
    var monthRecords: [SessionRecord] { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"; let prefix = f.string(from: Date()); return model.visibleRecords.filter { $0.dayKey.hasPrefix(prefix) } }
}
struct SessionFlow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let result = model.result { ResultScreen(record: result, close: { model.closeResult(); dismiss() }) }
                else if let record = model.active { if record.phase == .finished { ResultScreen(record: record, close: { model.closeResult(); dismiss() }) } else { ActiveSessionScreen(record: record) } }
                else { Color.clear.onAppear { dismiss() } }
            }.background(EnchantTheme.background).navigationBarTitleDisplayMode(.inline)
        }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("知道了") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
        .privacySensitive()
    }
}
struct ActiveSessionScreen: View {
    @EnvironmentObject var model: AppModel
    let record: SessionRecord
    @State private var discard = false
    var body: some View {
        TabView {
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                Illustration(name: "Sword", size: 56)
                Text(L10n.text(record.phase == .interrupted ? "中断记录" : record.phase == .paused ? "已暂停" : "正在附魔")).font(EnchantTheme.title()).foregroundStyle(EnchantTheme.magic)
                Text(SessionRecord.durationString(record.activeDuration(at: model.now))).font(EnchantTheme.digits(44)).minimumScaleFactor(0.5).lineLimit(1).accessibilityIdentifier("session-timer")
                Text(L10n.format("活动时长 · %@开始", record.originLabel)).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted)
                EnchantCard { HStack { MetricView(title: "心率 · bpm", value: model.currentHeartRate(for: record).map { String(Int($0.rounded())) } ?? "--"); MetricView(title: "次数 · 估算", value: record.cycleEstimate.map(String.init) ?? "--", color: EnchantTheme.magic) } }
                if let count = model.idleCountdown { Button(L10n.format("静止，%ld秒后结束 · 继续", count)) { model.continueAfterIdle() }.foregroundStyle(EnchantTheme.gold) }
                Spacer(minLength: 0)
                HStack(spacing: 12) { Button(L10n.text(record.phase == .recording ? "暂停" : "继续")) { if record.phase == .recording { model.pause() } else { model.resume() } }.buttonStyle(EnchantButton(secondary: true)); Button("结束") { model.finish() }.buttonStyle(EnchantButton()).accessibilityLabel("结束附魔") }
            }.padding(20).padding(.bottom, 18)
            VStack(spacing: 20) {
                Text("本次战况").font(EnchantTheme.title()); HeartChart(record: record)
                EnchantCard { HStack { MetricView(title: "次/分 · 估算", value: record.cycleEstimate.map { String(Int(Double($0) / max(1, record.activeDuration(at: model.now)) * 60)) } ?? "--"); MetricView(title: "已采样", value: "\(record.validHeartSamples.count)") } }
                Text(record.phase == .interrupted ? L10n.text("检查点已保留，停机时间没有计入。") : model.motionStatus).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted)
                Button(L10n.text(record.origin == .automatic ? "误触发，丢弃" : "丢弃记录"), role: .destructive) { discard = true }.frame(minHeight: 44)
            }.padding(24).padding(.bottom, 20)
        }.tabViewStyle(.page(indexDisplayMode: .always)).background(EnchantTheme.background).navigationTitle("本次记录")
        .confirmationDialog("丢弃这次记录？", isPresented: $discard, titleVisibility: .visible) { Button("丢弃", role: .destructive) { model.discardActive() } }
    }
}
struct ResultScreen: View {
    @EnvironmentObject var model: AppModel
    let record: SessionRecord
    let close: () -> Void
    @State private var editing = false
    @State private var discard = false
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Illustration(name: "Sword", size: min(110, geometry.size.height * 0.16))
                    Text("附魔完成").font(EnchantTheme.title()).foregroundStyle(EnchantTheme.gold)
                }
                VStack(spacing: 6) { Text(record.formattedDuration).font(EnchantTheme.digits(geometry.size.height < 600 ? 36 : 40)); Text("活动时长").font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted) }
                EnchantCard { HStack { MetricView(title: "次数 · 估算", value: record.cycleEstimate.map(String.init) ?? "--"); MetricView(title: "平均心率 · bpm", value: record.averageHeartRate.map { String(Int($0.rounded())) } ?? "--", color: EnchantTheme.magic) } }
                if model.engine != nil { Text("保存未完成，结果已保留").font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.danger) }
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    if model.engine != nil { Button("重试保存") { model.saveFinished() }.buttonStyle(EnchantButton()) }
                    else { Button("备注") { editing = true }.buttonStyle(EnchantButton(secondary: true)); Button("完成", action: close).buttonStyle(EnchantButton()) }
                }
            }.padding(geometry.size.height < 600 ? 16 : 20).frame(width: geometry.size.width, height: geometry.size.height)
        }.navigationTitle("本次战况").toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Button("丢弃记录", role: .destructive) { discard = true } } label: { Text("···").font(EnchantTheme.body(24)) } } }
        .sheet(isPresented: $editing) { RecordEditor(existing: model.records.first { $0.id == record.id } ?? record) }
        .confirmationDialog("丢弃这条记录？", isPresented: $discard, titleVisibility: .visible) { Button("丢弃", role: .destructive) { let discarded = model.engine != nil ? model.discardActive() : model.delete(record.id); if discarded { close() } } }
    }
}
