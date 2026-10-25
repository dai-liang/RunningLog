import SwiftUI

/// 新建和编辑共享表单，所有修改在保存前只保留于局部状态。
struct RecordEditor: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.dismiss) private var dismiss
    private let original: RunRecord?
    @State private var date: Date
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var distance: String
    @State private var feeling: RunFeeling
    @State private var note: String
    @State private var validationError: String?

    init(record: RunRecord? = nil) {
        original = record
        let value = record ?? RunRecord()
        _date = State(initialValue: value.date)
        _hours = State(initialValue: Int(value.duration) / 3600)
        _minutes = State(initialValue: Int(value.duration) % 3600 / 60)
        _seconds = State(initialValue: Int(value.duration) % 60)
        _distance = State(initialValue: value.distance > 0 ? String(value.distance) : "")
        _feeling = State(initialValue: value.feeling)
        _note = State(initialValue: value.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("跑步时间", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                } header: { Text("什么时候跑的") } footer: { Text("默认当前日期和时间，也可以补记以前的跑步。") }
                Section("跑了多久") {
                    Stepper("\(hours) 小时", value: $hours, in: 0...24)
                    Stepper("\(minutes) 分钟", value: $minutes, in: 0...59)
                    Stepper("\(seconds) 秒", value: $seconds, in: 0...59)
                }
                Section {
                    HStack {
                        Text("距离")
                        TextField("选填", text: $distance).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .accessibilityLabel("距离，公里").accessibilityIdentifier("recordDistance")
                        Text("公里").foregroundStyle(.secondary)
                    }
                    Picker("感受", selection: $feeling) {
                        ForEach(RunFeeling.allCases) { value in Text(value.rawValue).tag(value) }
                    }
                    if let km = Double(distance), km > 0 {
                        LabeledContent("平均配速", value: RunFormat.pace(Double(hours * 3600 + minutes * 60 + seconds) / km) + " /公里")
                    }
                } header: { Text("这次的状态") } footer: { Text("未填写距离时，仍统计次数与时长，但不计算配速。") }
                Section("跑步手记") {
                    TextField("路线、天气，或一点小感受…", text: $note, axis: .vertical).lineLimit(3...7).accessibilityIdentifier("recordNote")
                    Text("\(note.count)/2000 字").font(.caption).foregroundStyle(.secondary)
                }
                if let validationError { Section { Text(validationError).foregroundStyle(.red) } }
            }
            .navigationTitle(original == nil ? "记一次跑步" : "编辑跑步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).accessibilityIdentifier("saveRecord").bold().disabled(!store.storageAvailable) }
            }
        }
    }

    private func save() {
        let text = distance.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "，", with: ".").replacingOccurrences(of: ",", with: ".")
        guard let km = text.isEmpty ? 0 : Double(text) else { validationError = "请输入有效的公里数。"; return }
        let value = RunRecord(id: original?.id ?? UUID(), date: date,
                              duration: Double(hours * 3600 + minutes * 60 + seconds),
                              distance: km, feeling: feeling, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        do { try store.save(value); dismiss() }
        catch { validationError = error.localizedDescription }
    }
}
