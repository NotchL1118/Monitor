import SwiftUI

/// Keeps optional browser setup out of the report's vertical layout.
struct ChromeConnectionNotice: View {
    @EnvironmentObject private var model: MonitorModel
    @State private var isPresented = false
    @State private var hasViewed = false

    var body: some View {
        Group {
            if !model.browserConnected {
                Button {
                    hasViewed = true
                    isPresented.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "puzzlepiece.extension")
                        Text("连接 Chrome")
                        Circle().fill(Palette.green)
                            .frame(width: 5, height: 5)
                            .opacity(hasViewed ? 0 : 1)
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(Palette.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Palette.green.opacity(isPresented ? 0.3 : 0.12)))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("查看 Chrome 扩展连接提示")
                .accessibilityLabel("连接 Chrome，查看提示")
                .accessibilityValue(isPresented ? "已展开" : "已收起")
                .popover(isPresented: $isPresented, arrowEdge: .top) {
                    details
                        .onExitCommand { isPresented = false }
                }
            }
        }
        .onChange(of: model.browserConnected) { _, _ in
            isPresented = false
            hasViewed = false
        }
        .onChange(of: model.dashboardPage) { _, _ in isPresented = false }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 17))
                    .padding(10)
                    .background(Palette.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark").font(.system(size: 12))
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                    .accessibilityLabel("关闭连接提示")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("连接 Chrome，补全浏览时间")
                    .font(.system(size: 16, weight: .semibold))
                Text("安装并配对 Chrome 扩展后，即可在 Monitor 中查看每个网站的使用时间。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                Divider()
                HStack {
                    Text("应用统计")
                    Spacer()
                    Text(applicationStatus).foregroundStyle(Palette.muted)
                }
                HStack {
                    Text("网站统计")
                    Spacer()
                    Text("等待连接").foregroundStyle(Palette.muted)
                }
                Divider()
            }.font(.system(size: 12))
            HStack {
                Button("稍后再说") { isPresented = false }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted)
                Spacer()
                Button("查看连接步骤") {
                    isPresented = false
                    model.dashboardPage = .connection
                }.buttonStyle(.borderedProminent).tint(Palette.green)
            }.font(.system(size: 12))
        }
        .padding(22).frame(width: 344)
        .foregroundStyle(Palette.ink)
        .background(.white)
        .preferredColorScheme(.light)
    }

    private var applicationStatus: String {
        if model.storageError != nil { return "记录异常" }
        if model.paused { return "已暂停" }
        return model.recording ? "正常记录" : "等待恢复"
    }
}
