import SwiftUI

/// 四个主标签页（状态 / 功能 / 蓝牙 / 系统）共用的页面框架。
///
/// - 紧凑大标题：粗体大标题与导航栏同一行（`inlineLarge`），省去系统大标题额外占用的一整行高度；
/// - 页面底色铺到状态栏下方，导航栏底色与页面一致，滚动时由系统材质接管；
/// - 标题文字与底部标签名保持一致。
struct P4RootPage: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
            .background(Color.p4Background.ignoresSafeArea())
            .overlay(alignment: .bottom) { ToastOverlay() }
    }
}

extension View {
    func p4RootPage(_ title: String) -> some View {
        modifier(P4RootPage(title: title))
    }
}

/// 系统分享面板（导出日志、诊断包共用）。
struct P4ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
