import SwiftUI

struct RecordListView: View {
    @EnvironmentObject private var store: RunStore
    @State private var search = ""
    @State private var filter: ListFilter = .all
    @State private var adding = false
    @State private var editing: RunRecord?
    @State private var deleting: RunRecord?
    private enum ListFilter: String, CaseIterable { case all = "全部", month = "本月", year = "今年" }
    private var filtered: [RunRecord] {
        store.records.filter { record in
            let range = (filter == .month ? RunPeriod.month : .year).interval(containing: Date(), calendar: store.calendar)
            let matchesTime = filter == .all || (record.date >= range.start && record.date < range.end)
            let matchesSearch = search.isEmpty || record.note.localizedCaseInsensitiveContains(search) || record.feeling.rawValue.contains(search)
            return matchesTime && matchesSearch
        }
    }
    private var months: [Date] {
        Set(filtered.map { store.calendar.dateInterval(of: .month, for: $0.date)!.start }).sorted(by: >)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("时间范围", selection: $filter) { ForEach(ListFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    Text("共 \(filtered.count) 次 · \(RunFormat.duration(filtered.reduce(0) { $0 + $1.duration }))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "还没有跑步记录" : "未找到记录", systemImage: "figure.run", description: Text(search.isEmpty ? "点击右上角 +，记下你的第一次跑步。" : "试试其他备注或感受关键词。"))
                        .listRowBackground(Color.clear)
                }
                ForEach(months, id: \.self) { month in
                    Section(month.formatted(.dateTime.year().month(.wide))) {
                        ForEach(filtered.filter { store.calendar.isDate($0.date, equalTo: month, toGranularity: .month) }) { record in
                            Button { editing = record } label: { RecordRow(record: record) }.buttonStyle(.plain).accessibilityIdentifier("record-" + record.note)
                                .swipeActions {
                                    Button(role: .destructive) { deleting = record } label: { Label("删除", systemImage: "trash") }
                                    Button { editing = record } label: { Label("编辑", systemImage: "pencil") }.tint(.teal)
                                }
                                .contextMenu {
                                    Button("编辑", systemImage: "pencil") { editing = record }
                                    Button("删除", systemImage: "trash", role: .destructive) { deleting = record }
                                }
                        }
                    }
                }
            }
            .navigationTitle("跑步记录")
            .searchable(text: $search, prompt: "搜索备注或跑步感受")
            .toolbar { Button { adding = true } label: { Label("添加记录", systemImage: "plus") }.accessibilityIdentifier("addRecord").disabled(!store.storageAvailable) }
            .sheet(isPresented: $adding) { RecordEditor() }
            .sheet(item: $editing) { RecordEditor(record: $0) }
            .confirmationDialog("删除这次跑步？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("删除记录", role: .destructive) { if let record = deleting { store.delete(record) }; deleting = nil }
                Button("取消", role: .cancel) { deleting = nil }
            } message: { Text("删除后无法撤销，统计也会同步更新。") }
        }
    }
}

/// 列表同时展示未填写距离的情况，避免将其误解为一次零配速跑步。
private struct RecordRow: View {
    let record: RunRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(record.date.formatted(.dateTime.month().day().weekday(.abbreviated))).font(.headline)
                Spacer()
                Label(record.feeling.rawValue, systemImage: record.feeling.symbol).font(.caption).foregroundStyle(.teal)
            }
            HStack {
                Text(RunFormat.duration(record.duration)).fontWeight(.semibold)
                Spacer()
                Text(record.distance > 0 ? "\(record.distance.formatted(.number.precision(.fractionLength(0...2)))) 公里" : "未记距离")
            }.font(.subheadline)
            if !record.note.isEmpty { Text(record.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            Text(record.date.formatted(.dateTime.hour().minute()) + (record.distance > 0 ? " · \(RunFormat.pace(record.duration / record.distance)) /公里" : ""))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
            // 为卡片留白指定命中区域，确保点击任意位置都能打开编辑页。
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
}
