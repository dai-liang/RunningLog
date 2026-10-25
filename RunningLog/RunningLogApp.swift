import SwiftUI
import CloudKit

@main
struct RunningLogApp: App {
    @StateObject private var store = RunStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .preferredColorScheme(store.settings.appearance == 0 ? nil : store.settings.appearance == 1 ? .light : .dark)
        }
    }
}

/// 全局错误统一展示；各表单的校验错误留在表单内部，便于立即修正。
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: RunStore
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("概览", systemImage: "chart.bar.xaxis") }
            RecordListView().tabItem { Label("记录", systemImage: "figure.run") }
            SettingsView().tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .tint(.teal)
        // 前台每分钟检查其他设备的更新；退到后台自动取消，不宣称系统后台实时同步。
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.syncNow()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await store.syncNow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task { await store.syncNow() }
        }
        .alert("操作未完成", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
