import SwiftUI

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
    @EnvironmentObject private var store: RunStore
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("概览", systemImage: "chart.bar.xaxis") }
            RecordListView().tabItem { Label("记录", systemImage: "figure.run") }
            SettingsView().tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .tint(.teal)
        .alert("操作未完成", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
