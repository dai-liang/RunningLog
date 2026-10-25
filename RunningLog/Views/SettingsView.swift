import SwiftUI
import UniformTypeIdentifiers

/// 系统文件选择器负责备份读写，不申请照片、位置或健康数据权限。
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @EnvironmentObject private var store: RunStore
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmImport = false
    @State private var document = BackupDocument()
    @State private var pendingData: Data?
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("每周 \(store.settings.weeklyCount) 次", value: setting(\.weeklyCount), in: 1...21)
                    Stepper("每周 \(store.settings.weeklyMinutes) 分钟", value: setting(\.weeklyMinutes), in: 10...3000, step: 10)
                } header: { Text("我的跑步目标") } footer: { Text("目标用于记录个人进度，可按自己的节奏调整。") }
                Section("显示偏好") {
                    Toggle("每周从周一开始", isOn: setting(\.mondayFirst))
                    Picker("外观", selection: setting(\.appearance)) {
                        Text("跟随系统").tag(0); Text("浅色").tag(1); Text("深色").tag(2)
                    }
                }
                Section {
                    Button { export() } label: { Label("导出 JSON 备份", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("导入 JSON 备份", systemImage: "square.and.arrow.down") }
                } header: { Text("数据与备份") } footer: {
                    Text("记录仅存储在本机，卸载应用可能丢失数据，请定期导出。导入会合并记录，同编号的记录以备份为准；保留本机设置。")
                }
                Section("关于跑步手记") {
                    Label("专注记录，无需账号", systemImage: "lock.shield")
                    LabeledContent("当前记录", value: "\(store.records.count) 次")
                    LabeledContent("版本", value: "1.0.0")
                    Text("支持手动补记与修改。暂不包含 GPS 追踪、Apple 健康同步或云同步。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .disabled(!store.storageAvailable)
            .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                          defaultFilename: "跑步手记-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                switch result { case .success: message = "备份已导出。"; case .failure(let error): message = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    // 先检查文件大小，避免读取过大的外部文件。
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 20_000_000 else { throw RunError.invalid("备份不能超过 20 MB。") }
                    let data = try Data(contentsOf: url)
                    let archive = try JSONDecoder().decode(RunArchive.self, from: data)
                    try archive.validate()
                    pendingData = data; confirmImport = true
                } catch { message = "导入失败：\(error.localizedDescription)" }
            }
            .confirmationDialog("合并备份记录？", isPresented: $confirmImport, titleVisibility: .visible) {
                Button("合并导入") {
                    do { if let pendingData { let count = try store.importBackup(pendingData); message = "已合并 \(count) 条备份记录。" } }
                    catch { message = error.localizedDescription }
                    pendingData = nil
                }
                Button("取消", role: .cancel) { pendingData = nil }
            } message: { Text("本机独有记录将保留，同编号记录会被备份内容更新。") }
            .alert("数据备份", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") { message = nil }
            } message: { Text(message ?? "") }
        }
    }
    /// 所有偏好统一经存储层保存，避免界面直接改动持久化状态。
    private func setting<Value>(_ path: WritableKeyPath<RunSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: path] }, set: { value in
            var updated = store.settings; updated[keyPath: path] = value; store.updateSettings(updated)
        })
    }
    private func export() {
        do { document = BackupDocument(data: try store.backup()); exporting = true }
        catch { message = error.localizedDescription }
    }
}
