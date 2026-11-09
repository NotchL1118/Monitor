import AppKit
import SwiftUI
import MonitorCore

enum Palette {
    static let background = Color(red: 0.96, green: 0.96, blue: 0.94)
    static let ink = Color(red: 0.16, green: 0.22, blue: 0.20)
    static let green = Color(red: 0.24, green: 0.40, blue: 0.32)
    static let muted = Color(red: 0.47, green: 0.51, blue: 0.47)
    static let orange = Color(red: 0.75, green: 0.43, blue: 0.26)
}

struct DashboardView: View {
    @EnvironmentObject private var model: MonitorModel
    @State private var confirmDelete = false
    @State private var pendingRetention: (retention: DataRetention, cutoff: Date, count: Int)?
    @State private var presentedModule: OverviewModule?
    @FocusState private var focusedModule: OverviewModule?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        switch model.dashboardPage {
                        case .overview: overview
                        case .applications: applicationAnalysis
                        case .dayTimeline: DayTimelineView()
                        case .connection: connection.onAppear { model.refreshStorageUsage() }
                        }
                        if let error = model.storageError { message(error, symbol: "exclamationmark.triangle", color: .red) }
                        if let error = model.serverError { message(error, symbol: "exclamationmark.triangle", color: Palette.orange) }
                    }.padding(32).id("page-top")
                }
                .scrollDisabled(presentedModule != nil)
                // Only page navigation resets scrolling; switching apps keeps the current position.
                .onChange(of: model.dashboardPage) { _, _ in
                    presentedModule = nil
                    proxy.scrollTo("page-top", anchor: .top)
                }
            }
        }
        .background(Palette.background)
        .disabled(presentedModule != nil)
        .accessibilityHidden(presentedModule != nil)
        .overlayPreferenceValue(OverviewModuleBounds.self) { bounds in
            if let module = presentedModule, let anchor = bounds[module] {
                GeometryReader { geometry in
                    OverviewModuleOverlay(module: module, source: geometry[anchor], size: geometry.size) {
                        presentedModule = nil
                        focusedModule = module
                    } content: { expanded, close in
                        moduleContent(module, close: expanded ? close : nil)
                    }
                    .id(module)
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
        .environment(\.calendar, model.reportCalendar)
        .environment(\.timeZone, model.reportTimeZone.timeZone)
        .alert("清空所有使用记录？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("清空记录", role: .destructive) { model.deleteHistory() }
        } message: { Text("这会删除本机保存的所有日期记录，无法撤销。配对设置会保留。") }
        .alert("删除较早的记录？", isPresented: Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } })) {
            Button("取消", role: .cancel) { pendingRetention = nil }
            Button("删除并保存设置", role: .destructive) {
                if let pending = pendingRetention { model.setDataRetention(pending.retention) }
                pendingRetention = nil
            }
        } message: {
            if let pending = pendingRetention {
                Text("改为「\(pending.retention.label)」后，会立即删除 \(pending.cutoff.formatted(model.reportTimeZone.formatStyle.year().month().day())) 之前结束的 \(pending.count) 条记录，无法撤销。")
            }
        }
        .alert("Monitor", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("知道了") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                BrandPortrait().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Monitor").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("时间足迹").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.padding(.top, 28).padding(.bottom, 10)

            VStack(spacing: 8) {
                navigation("时间概览", symbol: "square.grid.2x2", id: .overview)
                navigation("应用分析", symbol: "chart.xyaxis.line", id: .applications)
                navigation("一日时间线", symbol: "point.3.connected.trianglepath.dotted", id: .dayTimeline)
                navigation("连接与设置", symbol: "slider.horizontal.3", id: .connection)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                MascotAvatar(state: model.mascot, size: 46)
                HStack(spacing: 7) {
                    Circle().fill(model.recording ? Palette.green : Palette.orange).frame(width: 7, height: 7)
                    Text(model.recording ? "正在记录" : (model.paused ? "已暂停" : "等待恢复"))
                        .font(.system(size: 12, weight: .medium))
                }
                Text(model.recording ? model.currentApp : "给自己留一点空白。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                Button { model.togglePause() } label: {
                    Label(model.paused ? "继续记录" : "暂停记录", systemImage: model.paused ? "play" : "pause")
                        .font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.plain).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
            }.padding(14).background(Palette.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            Label("只存本机 · 由你掌控", systemImage: "lock.shield")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 20).padding(.bottom, 24).frame(width: 200)
        .background(Color(red: 0.92, green: 0.93, blue: 0.90))
    }

    private func navigation(_ title: String, symbol: String, id: DashboardPage) -> some View {
        Button {
            if id == .applications, model.selectedApplication == nil, let app = model.listedApplications.first {
                model.selectedApplication = ActivityIdentity(key: app.key, name: app.name)
            }
            model.dashboardPage = id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18)
                Text(title).font(.system(size: 13, weight: model.dashboardPage == id ? .semibold : .regular))
                Spacer()
            }.padding(12).background(model.dashboardPage == id ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }

    private var overview: some View {
        Group {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR TIME, IN VIEW").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Palette.muted)
                    Text("把时间，看清楚。").font(.system(size: 30, weight: .semibold))
                    Text("从每一次打开，到今天的全貌。").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { model.exportReport() } label: { Label("导出所选时段", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.bordered).controlSize(.regular)
                ChromeConnectionNotice()
            }
            ReportPicker().id("report-range")
            overviewCards
        }
    }

    private var applicationAnalysis: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("A CLOSER LOOK").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Palette.muted)
                Text("应用里的时间。").font(.system(size: 30, weight: .semibold))
                Text("选择一个应用，看看每段时间是怎样度过的。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            ReportPicker().id("report-range")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.listedApplications) { app in
                        Button { model.showApplication(ActivityIdentity(key: app.key, name: app.name)) } label: {
                            HStack(spacing: 7) {
                                ActivityIcon(key: app.key, kind: .application).frame(width: 24, height: 24)
                                Text(app.name).font(.system(size: 12, weight: .medium))
                            }.padding(.horizontal, 12).padding(.vertical, 9)
                                .background(model.selectedApplication?.key == app.key ? Palette.green.opacity(0.10) : .white,
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                                    model.selectedApplication?.key == app.key ? Palette.green.opacity(0.4) : .clear))
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(model.selectedApplication?.key == app.key ? .isSelected : [])
                    }
                }
            }.scrollIndicators(.hidden)
            if let report = model.applicationReport {
                ApplicationDetailView(report: report)
            } else {
                ContentUnavailableView("选择一个应用", systemImage: "chart.xyaxis.line",
                    description: Text(model.applicationReportError ?? "所选时段有记录的应用会显示在这里。"))
            }
        }
    }

    private var overviewCards: some View {
        Group {
            HStack(spacing: 14) {
                statistic("电脑前台时长", value: durationText(model.appSeconds), symbol: "desktopcomputer", footnote: "已记录应用时长之和", accent: Palette.green)
                statistic("网站浏览时长", value: durationText(model.websiteSeconds), symbol: "globe", footnote: "属于 Chrome 时长的一部分", accent: Palette.orange)
                statistic("使用过的应用", value: "\(model.listedApplications.count) 个", symbol: "square.stack.3d.up", footnote: "\(model.listedWebsites.count) 个网站留下足迹", accent: Palette.green)
            }
            HStack(alignment: .top, spacing: 16) {
                preview(.ranking(.application))
                preview(.ranking(.website))
            }
            preview(.timeline)
            Text("统计的是前台停留时间，不代表实际注意力。锁屏与休眠暂停计时；没有键鼠操作时仍会记录。")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private func preview(_ module: OverviewModule) -> some View {
        Button { presentedModule = module } label: {
            moduleContent(module, close: nil)
                .overviewCardSurface(module)
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .focused($focusedModule, equals: module)
        .accessibilityLabel("展开\(module.title)模块")
        .anchorPreference(key: OverviewModuleBounds.self, value: .bounds) { [module: $0] }
        .opacity(presentedModule == module ? 0 : 1)
    }

    @ViewBuilder private func moduleContent(_ module: OverviewModule, close: (() -> Void)?) -> some View {
        switch module {
        case .ranking(let kind):
            RankingCard(kind: kind, items: kind == .application ? model.listedApplications : model.listedWebsites,
                        reportLabel: model.reportLabel, selectedApplicationKey: model.selectedApplication?.key,
                        showApplication: model.showApplication, close: close)
        case .timeline:
            timelineCard(close: close)
        }
    }

    private func statistic(_ title: String, value: String, symbol: String, footnote: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(title).font(.system(size: 12)); Spacer(); Image(systemName: symbol).foregroundStyle(accent) }
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(footnote).font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func timelineCard(close: (() -> Void)?) -> some View {
        let items = close == nil ? model.timeline.prefix(8) : model.timeline[...]
        return VStack(alignment: .leading, spacing: 16) {
            OverviewModuleHeader(module: .timeline, subtitle: "最近 \(items.count) 条", close: close)
            if items.isEmpty {
                Text("打开一个应用，第一段时间就会出现在这里。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.vertical, 14)
            } else if close != nil {
                Text(model.reportLabel).font(.system(size: 11)).foregroundStyle(Palette.muted)
                ScrollView { timelineRows(items).padding(.trailing, 6) }
            } else {
                timelineRows(items)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func timelineRows(_ items: ArraySlice<ActivitySlice>) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    Text(timelineLabel(item))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                        .frame(width: model.period == .day ? 175 : 202, alignment: .leading)
                    Circle().fill(item.kind == .application ? Palette.green : Palette.orange).frame(width: 6, height: 6)
                    Text(item.name).font(.system(size: 12)).lineLimit(1)
                    Text(item.kind == .website ? "网站" : "应用").font(.system(size: 9)).foregroundStyle(Palette.muted)
                    Spacer()
                    Text(durationText(item.seconds)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.padding(.vertical, 10)
                Divider().opacity(0.4)
            }
        }
    }

    private func timelineLabel(_ item: ActivitySlice) -> String {
        let showDate = model.period != .day
        let crossesMidnight = !model.reportCalendar.isDate(item.start, inSameDayAs: item.end)
        func label(_ date: Date, showDate: Bool) -> String {
            date.formatted(Date.FormatStyle(date: showDate ? .numeric : .omitted, time: .standard,
                locale: Locale(identifier: "zh_CN"), calendar: model.reportCalendar, timeZone: model.reportTimeZone.timeZone))
        }
        let start = label(item.start, showDate: showDate)
        let end = label(item.end, showDate: crossesMidnight)
        return "\(start) – \(end)"
    }

    private var connection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("CONNECTED, LOCALLY").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Palette.muted)
                Text("连接你的浏览时间。").font(.system(size: 30, weight: .semibold))
                Text("一次配对，之后只需让 Monitor 保持运行。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 16) {
                Label("时间与时区", systemImage: "clock").font(.system(size: 17, weight: .semibold))
                HStack {
                    Text("展示与统计时区").font(.system(size: 13))
                    Spacer()
                    Picker("展示与统计时区", selection: $model.reportTimeZone) {
                        ForEach(ReportTimeZone.allCases, id: \.self) { zone in Text(zone.label).tag(zone) }
                    }.labelsHidden().pickerStyle(.menu).frame(width: 235)
                }
                Text("日期范围、图表、使用明细和菜单栏仪表盘统一使用所选时区。切换后会重新划分每天的记录，原始记录与实际使用时长不变。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
                Text("北京时间固定为东八区（UTC+8），不受 Mac 的系统时区影响。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(26).background(.white, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label("Chrome 扩展", systemImage: "puzzlepiece.extension").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text(model.browserConnected ? "已连接" : "等待连接")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(model.browserConnected ? Palette.green : Palette.orange)
                }
                step(1, title: "在 Chrome 中加载扩展", detail: "打开 chrome://extensions，开启右上角「开发者模式」，点击「加载已解压的扩展程序」，选择配套的 ChromeExtension 文件夹。")
                if let bundled = Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension"), FileManager.default.fileExists(atPath: bundled.path) {
                    Button("在 Finder 中显示扩展文件夹") { NSWorkspace.shared.selectFile(bundled.path, inFileViewerRootedAtPath: "") }
                        .buttonStyle(.bordered)
                }
                step(2, title: "复制本机配对码", detail: "配对码只用于让扩展连接这台 Mac。请不要分享给其他人。")
                Button { model.copyPairingCode() } label: { Label("复制配对码", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderedProminent).tint(Palette.green).disabled(model.pairingToken.isEmpty)
                step(3, title: "在扩展中连接", detail: "点击 Chrome 工具栏中的机娘图标，粘贴配对码并点击「连接本机」。打开普通网页后，页面停留时间就会开始记录。已有扩展请在 chrome://extensions 点击重新加载，升级到 0.3.0；原有配对会保留。")
                Divider()
                Label(model.serverReady ? "本机服务运行中 · 127.0.0.1:47821" : "本机服务尚未就绪", systemImage: "network")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(26).background(.white, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 18) {
                Text("你的数据，留在这里。").font(.system(size: 17, weight: .semibold))
                Text("记录应用名称，以及 Chrome 前台网页的域名、标题、地址和起止时间。地址可能包含搜索词和查询参数；不会读取网页正文、键盘输入或屏幕内容，不请求网站图标，不上传到服务器。网址中的用户名和密码会移除。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(5)
                Text("Chrome 扩展仅记录前台普通窗口；后台标签页、无痕窗口、浏览器设置页不计入网站时长。应用统计仍会包含这些窗口中的 Chrome 前台时间。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(5)
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 14))
            storageCard
            message("关闭窗口后仍会在菜单栏记录。退出 Monitor 会停止应用和网站统计；再次打开后自动恢复。", symbol: "info.circle", color: Palette.muted)
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("存储与保留", systemImage: "internaldrive").font(.system(size: 17, weight: .semibold))
            HStack(alignment: .top, spacing: 12) {
                storageTile("占用空间", symbol: "externaldrive", footnote: sizeFootnote) {
                    Text(model.storageUsage?.sizeText ?? "—")
                }
                storageTile("已记录", symbol: "calendar", footnote: earliestFootnote) {
                    Text(recordedDays.map { "\($0) 天" } ?? "—")
                }
                storageTile("保留期限", symbol: "clock.arrow.circlepath", footnote: retentionFootnote) {
                    Menu {
                        Picker("保留期限", selection: retentionBinding) {
                            ForEach(DataRetention.allCases, id: \.self) { retention in Text(retention.label).tag(retention) }
                        }.pickerStyle(.inline).labelsHidden()
                    } label: {
                        HStack(spacing: 6) {
                            Text(model.dataRetention.shortLabel)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.green)
                        }.contentShape(Rectangle())
                    }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "folder").foregroundStyle(Palette.muted)
                Text(model.dataDirectory.path).font(.system(size: 11, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 12)
                Button("在 Finder 中打开") { NSWorkspace.shared.open(model.dataDirectory) }.buttonStyle(.bordered).controlSize(.small)
            }.padding(.horizontal, 14).padding(.vertical, 10)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
            Divider()
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("清空所有历史记录").font(.system(size: 13, weight: .medium))
                    Text("删除本机保存的全部使用记录，配对设置会保留。").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("清空…", role: .destructive) { confirmDelete = true }.buttonStyle(.bordered)
            }
        }.padding(26).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func storageTile<Value: View>(_ title: String, symbol: String, footnote: String,
                                          @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted)
                Spacer()
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Palette.green)
            }
            value().font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(footnote).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(Palette.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var retentionBinding: Binding<DataRetention> {
        Binding(get: { model.dataRetention }, set: { retention in
            if let pending = model.pendingDeletion(for: retention) {
                pendingRetention = (retention, pending.cutoff, pending.count)
            } else { model.setDataRetention(retention) }
        })
    }

    private var recordedDays: Int? {
        guard let usage = model.storageUsage else { return nil }
        guard let earliest = usage.earliest else { return 0 }
        let calendar = model.reportCalendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest),
                                           to: calendar.startOfDay(for: Date())).day ?? 0
        return max(0, days) + 1
    }

    private var sizeFootnote: String {
        guard let usage = model.storageUsage else { return "数据库与日志文件" }
        // Projection needs a week of history to be meaningful.
        guard let days = recordedDays, days >= 7 else { return "数据库与日志文件" }
        let yearly = Int64(Double(usage.bytes) / Double(days) * 365)
        return "按目前速度，一年约 \(ByteCountFormatter.string(fromByteCount: yearly, countStyle: .file))"
    }

    private var earliestFootnote: String {
        guard let earliest = model.storageUsage?.earliest else { return "暂无记录" }
        return "最早 \(earliest.formatted(model.reportTimeZone.formatStyle.year().month().day()))"
    }

    private var retentionFootnote: String {
        guard let cutoff = model.dataRetention.cutoff(now: Date(), calendar: model.reportCalendar) else {
            return "不会自动删除记录"
        }
        return "每天自动清理 \(cutoff.formatted(model.reportTimeZone.formatStyle.year().month().day())) 之前的记录"
    }

    private func step(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
                .background(Palette.green.opacity(0.09), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4).textSelection(.enabled)
            }
        }
    }

    private func message(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12)).foregroundStyle(color).lineSpacing(4)
    }
}

struct ActivityIcon: View {
    let key: String
    let kind: ActivityKind
    var body: some View {
        if kind == .application, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
        } else {
            Image(systemName: kind == .website ? "globe" : "app")
                .font(.system(size: 15)).foregroundStyle(kind == .website ? Palette.orange : Palette.green)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
