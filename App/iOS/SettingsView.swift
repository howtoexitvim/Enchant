import SwiftUI
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            HStack { PixelIcon(name: "settings", size: 24); Text("偏好设置").font(EnchantTheme.title()); Spacer() }.padding(.bottom, 8)
            preference("自动开始", icon: "play", value: $model.preferences.automaticStart)
            preference("静止提醒", icon: "pause", value: $model.preferences.autoStop)
            preference("记录心率", icon: "heart", value: $model.preferences.healthEnabled)
            preference("声音", icon: "sound", value: $model.preferences.sound)
            preference("触感", icon: "haptics", value: $model.preferences.haptics)
            NavigationLink { TrashView() } label: { HStack { PixelIcon(name: "trash", size: 28); Text("回收站"); Spacer(); Text("›").accessibilityHidden(true) }.padding(.horizontal, 16).frame(minHeight: 52).background(EnchantTheme.surface, in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain).accessibilityLabel("回收站")
            Spacer(minLength: 0)
            Text("自动开始需保持 Watch 前台；心率只显示有效样本。").font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
            Text(model.connectivity.status).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).lineLimit(2).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
        }.padding(20).background(EnchantTheme.background).navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
    }
    private func preference(_ title: String, icon: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            PixelIcon(name: icon, color: EnchantTheme.magic, size: 20)
            Text(L10n.text(title)).font(EnchantTheme.body())
            Spacer(minLength: 0)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).accessibilityLabel(LocalizedStringKey(title))
        }.padding(.horizontal, 16).frame(minHeight: 56).background(EnchantTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
struct TrashView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        List {
            if model.deletedRecords.isEmpty { EmptyState(title: "回收站为空", message: "已删除记录可恢复", icon: "trash") }
            ForEach(model.deletedRecords) { record in VStack(alignment: .leading, spacing: 12) { Text(L10n.format("%@ · %@", record.dayKey, record.formattedDuration)); Text(record.note.isEmpty ? L10n.format("%@记录", record.originLabel) : record.note).lineLimit(2).foregroundStyle(EnchantTheme.muted); Button("恢复") { model.restore(record.id) } } }
            if !model.deletedRecords.isEmpty { Text("恢复后会重新出现在两端手账中。").font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted) }
        }.scrollContentBackground(.hidden).background(EnchantTheme.background).navigationTitle("回收站")
    }
}
