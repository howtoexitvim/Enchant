import SwiftUI
import Charts
struct HeartChart: View {
    let record: SessionRecord
    var compact = false
    var height: CGFloat? = nil
    var body: some View {
        let segments = record.heartSegments
        let validSamples = record.validHeartSamples
        if segments.isEmpty {
            VStack(alignment: .leading, spacing: 8) { Text("心率未获取").font(EnchantTheme.body(16)); Text("未获读取权限或此时间段没有有效样本。").font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted) }
        } else {
            VStack(alignment: .leading, spacing: compact ? 5 : 12) {
                Text("本次心率").font(EnchantTheme.body(compact ? 14 : 16)).frame(height: compact ? 18 : nil)
                Chart {
                    ForEach(Array(segments.enumerated()), id: \.offset) { segmentIndex, samples in
                        ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                            LineMark(x: .value(L10n.text("时间"), sample.date), y: .value(L10n.text("心率"), sample.bpm), series: .value(L10n.text("连续样本"), segmentIndex)).foregroundStyle(EnchantTheme.magic)
                            PointMark(x: .value(L10n.text("时间"), sample.date), y: .value(L10n.text("心率"), sample.bpm)).foregroundStyle(EnchantTheme.magic).symbolSize(12)
                        }
                    }
                }.frame(height: height ?? (compact ? 55 : 140)).chartYScale(domain: .automatic(includesZero: false)).chartXAxis(compact ? .hidden : .automatic)
                    .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisGridLine(); AxisValueLabel().font(EnchantTheme.digits(10)) } }
                Text(compact ? L10n.format("%ld 个有效样本", validSamples.count) : L10n.format("%ld 个样本 · 暂停和超过 30 秒的采样空缺断开显示", validSamples.count)).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).frame(height: compact ? 16 : nil)
                if !compact, !record.heartSources.isEmpty { Text(L10n.format("来源：%@", record.heartSources.map(L10n.heartSource).joined(separator: " · "))).font(EnchantTheme.body(12)).foregroundStyle(EnchantTheme.muted).lineLimit(1) }
            }
        }
    }
}
