import SwiftUI
import Charts

/// 统计锚点与所选维度独立保存，切换维度后仍可回顾同一时间段。
struct DashboardView: View {
    @EnvironmentObject private var store: RunStore
    @State private var period: RunPeriod = .week
    @State private var anchor = Date()
    @State private var adding = false
    @State private var metric: ChartMetric = .duration
    private enum ChartMetric: String, CaseIterable { case duration = "时长", count = "次数", distance = "距离" }
    private var interval: DateInterval { period.interval(containing: anchor, calendar: store.calendar) }
    private var summary: RunSummary { RunSummary(records: store.records, interval: interval) }
    private var weekly: RunSummary { RunSummary(records: store.records, interval: RunPeriod.week.interval(containing: Date(), calendar: store.calendar)) }
    private var isCurrent: Bool { interval.contains(Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("每一步，都算数。").font(.title2.bold())
                            Text("把坚持，留给未来的自己").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "figure.run.circle.fill").font(.system(size: 48)).foregroundStyle(.teal)
                    }
                    Picker("统计维度", selection: $period) {
                        ForEach(RunPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }.accessibilityLabel("上一\(period.rawValue)")
                        Spacer()
                        VStack(spacing: 3) {
                            Text(periodTitle).font(.headline)
                            Text(dateRange).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                            .disabled(isCurrent).accessibilityLabel("下一\(period.rawValue)")
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metricCard("跑步次数", value: "\(summary.count)", unit: "次", symbol: "figure.run", prominent: true)
                        metricCard("累计时长", value: RunFormat.clock(summary.duration), unit: "", symbol: "stopwatch")
                        metricCard("累计距离", value: String(format: "%.2f", summary.distance), unit: "公里", symbol: "point.bottomleft.forward.to.point.topright.scurvepath")
                        metricCard("平均配速", value: RunFormat.pace(summary.pace), unit: "/公里", symbol: "speedometer")
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("跑步分布").font(.headline)
                            Spacer()
                            Picker("图表指标", selection: $metric) { ForEach(ChartMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                                .pickerStyle(.menu)
                        }
                        if summary.count == 0 {
                            ContentUnavailableView("这段时间还没有跑步", systemImage: "shoeprints.fill", description: Text("添加一次记录，让坚持有迹可循。"))
                                .frame(minHeight: 180)
                        } else {
                            Chart(period.buckets(containing: anchor, calendar: store.calendar), id: \.start) { bucket in
                                let totals = RunSummary(records: store.records, interval: bucket)
                                BarMark(x: .value("日期", bucket.start, unit: period == .week || period == .month ? .day : .month),
                                        y: .value(metric.rawValue, chartValue(totals)))
                                    .foregroundStyle(.teal.gradient).cornerRadius(4)
                                    .accessibilityLabel(bucket.start.formatted(date: .abbreviated, time: .omitted))
                                    .accessibilityValue("\(chartValue(totals).formatted())\(metric == .duration ? "分钟" : metric == .count ? "次" : "公里")")
                            }
                            .chartYScale(domain: .automatic(includesZero: true))
                            .chartXAxis { AxisMarks(values: .stride(by: period == .week || period == .month ? .day : .month, count: period == .month ? 5 : 1)) { _ in AxisValueLabel(format: period == .week || period == .month ? .dateTime.day() : .dateTime.month(.abbreviated)) } }
                            .frame(height: 190)
                        }
                        Text("配速按有距离记录的总时长 ÷ 总距离计算。").font(.caption).foregroundStyle(.secondary)
                    }.padding().background(.background, in: RoundedRectangle(cornerRadius: 20))
                    goalCard
                    Button { adding = true } label: { Label("记一次跑步", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(8) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!store.storageAvailable)
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("跑步手记")
            .toolbar { if !isCurrent { Button("回到本\(period.rawValue)") { anchor = Date() } } }
            .sheet(isPresented: $adding) { RecordEditor() }
        }
    }
    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("本周的小目标", systemImage: "target").font(.headline)
                Spacer()
                Text("连续 \(RunStatistics.weekStreak(records: store.records, now: Date(), calendar: store.calendar)) 周").font(.caption.bold()).foregroundStyle(.teal)
            }
            Text("\(weekly.count) / \(store.settings.weeklyCount) 次").font(.title3.bold())
            ProgressView(value: min(Double(weekly.count) / Double(store.settings.weeklyCount), 1)).tint(.teal)
            Text("累计 \(Int(weekly.duration / 60)) / \(store.settings.weeklyMinutes) 分钟").font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: min(weekly.duration / Double(store.settings.weeklyMinutes * 60), 1)).tint(.orange)
            Text("本周未跑步时，连续周数保留至上周。").font(.caption).foregroundStyle(.secondary)
        }.padding().background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
    private func metricCard(_ title: String, value: String, unit: String, symbol: String, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.subheadline)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) { Text(value).font(.title.bold()); Text(unit).font(.caption) }
                VStack(alignment: .leading) { Text(value).font(.title2.bold()); Text(unit).font(.caption) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding()
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? Color.teal : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
    private var periodTitle: String {
        let year = store.calendar.component(.year, from: interval.start)
        if period == .year { return "\(year) 年" }
        if period == .quarter { return "\(year) 年 · 第 \((store.calendar.component(.month, from: interval.start) - 1) / 3 + 1) 季度" }
        return isCurrent ? "本\(period.rawValue)" : period == .month ? interval.start.formatted(.dateTime.year().month(.wide)) : "跑步周报"
    }
    private var dateRange: String {
        interval.start.formatted(.dateTime.month().day()) + " — " + interval.end.addingTimeInterval(-1).formatted(.dateTime.month().day())
    }
    private func shift(_ count: Int) { anchor = period.shifted(anchor, by: count, calendar: store.calendar) }
    private func chartValue(_ summary: RunSummary) -> Double {
        switch metric { case .duration: return summary.duration / 60; case .count: return Double(summary.count); case .distance: return summary.distance }
    }
}
