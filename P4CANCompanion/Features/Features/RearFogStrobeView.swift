import SwiftUI

/// 后雾灯爆闪：开始后固件持续注入 0x273（后雾灯位），单次最长 30 秒，结束自动恢复。
///
/// 与固件契约：
/// - `GET  /api/rear-fog-strobe/stats` → active / remainingMs / totalMs / intervalMs / pulses /
///   txOk / txFail / stockFogOn / templateValid / frameAgeMs / stopReason
/// - `POST /api/rear-fog-strobe/start` → 409 表示已在运行或还没收到整车 0x273
/// - `POST /api/rear-fog-strobe/stop`
struct RearFogStrobeView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var stats: P4JSON?
    @State private var busy = false
    @State private var errorText: String?

    private let pollInterval: Duration = .milliseconds(500)

    private var object: [String: P4JSON] { stats?.objectValue ?? [:] }
    private var isActive: Bool { object["active"]?.boolValue ?? false }
    private var remainingMs: Int { Int(object["remainingMs"]?.intValue ?? 0) }
    private var totalMs: Int { max(Int(object["totalMs"]?.intValue ?? 30_000), 1) }
    private var intervalMs: Int { Int(object["intervalMs"]?.intValue ?? 100) }
    private var templateValid: Bool { object["templateValid"]?.boolValue ?? false }
    private var setupMode: Bool { object["setupMode"]?.boolValue ?? false }

    private var progress: Double {
        guard isActive else { return 0 }
        return min(max(1 - Double(remainingMs) / Double(totalMs), 0), 1)
    }

    private var stateText: String {
        if isActive { return L10n.t("运行中", "Running") }
        if setupMode { return L10n.t("Setup 模式不可用", "Unavailable in setup mode") }
        return templateValid ? L10n.t("待机（已收到 0x273）", "Idle (0x273 seen)")
            : L10n.t("等待 0x273 帧", "Waiting for 0x273")
    }

    private var stateTone: P4Tone {
        if isActive { return .ok }
        return templateValid ? .info : .warn
    }

    private var canStart: Bool {
        !isActive && !busy && templateValid && !setupMode
    }

    private var stopReasonText: String {
        switch object["stopReason"]?.stringValue {
        case "USER_STOP": return L10n.t("手动停止", "Stopped manually")
        case "TIMEOUT": return L10n.t("30 秒到时自动停止", "Auto-stopped after 30 s")
        case "NO_FRAME": return L10n.t("收不到整车 0x273，已停止", "Stopped: no 0x273 from the car")
        default: return L10n.t("—", "—")
        }
    }

    var body: some View {
        List {
            Section {
                countdownCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    Task { await start() }
                } label: {
                    HStack(spacing: Theme.spacing(1)) {
                        Spacer()
                        if busy { ProgressView().controlSize(.small) }
                        Label(isActive ? L10n.t("爆闪中…", "Strobing…") : L10n.t("开始爆闪", "Start strobe"),
                              systemImage: "light.beacon.max")
                            .font(.body.weight(.semibold))
                        Spacer()
                    }
                }
                .disabled(!canStart)

                Button(role: .destructive) {
                    Task { await stop() }
                } label: {
                    HStack(spacing: Theme.spacing(1)) {
                        Spacer()
                        if busy { ProgressView().controlSize(.small) }
                        Label(L10n.t("停止", "Stop"), systemImage: "stop.fill")
                        Spacer()
                    }
                }
                .disabled(!isActive || busy)
            } footer: {
                Text(L10n.t("开始后立即注入 0x273，最长 30 秒后自动停止；停止后整车下一帧即恢复触发前的后雾灯状态。",
                            "Starts injecting 0x273 immediately, auto-stops after 30 s, and the car restores the previous fog state on its next frame."))
            }

            Section {
                // 顶部圆环下方已有「待机 / 爆闪中」胶囊，这里不再重复状态行。
                LabeledContent(L10n.t("间隔", "Interval"), value: "\(intervalMs) ms")
                LabeledContent(L10n.t("发送 / 失败", "TX / fail"),
                               value: "\(object["txOk"]?.intValue ?? 0) / \(object["txFail"]?.intValue ?? 0)")
                LabeledContent(L10n.t("触发前后雾灯", "Fog before start"),
                               value: (object["stockFogOn"]?.boolValue ?? false)
                                   ? L10n.t("开", "On") : L10n.t("关", "Off"))
                if !isActive {
                    LabeledContent(L10n.t("上次结束", "Last stop"), value: stopReasonText)
                }
            } header: {
                Label(L10n.t("运行状态", "Status"), systemImage: "gauge.with.dots.needle.33percent")
            }

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.p4Err)
                }
            }

            Section {
                Text(L10n.t("需要车辆上电、车身总线在线（能收到整车 0x273）。若一直停在「等待 0x273 帧」，说明这条总线没接或车型不发送该帧。",
                            "The car must be powered and the body bus online (0x273 must be received). If it stays on “Waiting for 0x273”, the bus or the frame is missing."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.t("后雾灯爆闪", "Rear Fog Strobe"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.p4Background, for: .navigationBar)
        .scrollContentBackground(.hidden)
        .background(Color.p4Background.ignoresSafeArea())
        .overlay(alignment: .bottom) { ToastOverlay() }
        .task { await poll() }
    }

    private var countdownCard: some View {
        VStack(spacing: Theme.spacing(1.5)) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isActive ? Color.p4OK : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.4), value: progress)
                VStack(spacing: 2) {
                    Text(isActive ? String(format: "%.1f", Double(remainingMs) / 1000) : "30.0")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    Text(isActive ? L10n.t("秒后自动停止", "s remaining") : L10n.t("单次上限 30 秒", "30 s max"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)
            .padding(.top, Theme.spacing(1))

            StatusChip(text: stateText, systemImage: stateTone.symbol, tone: stateTone)
            Text(L10n.t("后雾灯 · 0x273 byte2 bit7", "Rear fog · 0x273 byte2 bit7"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, Theme.spacing(1))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.spacing(1))
    }

    // MARK: - 读写

    private func poll() async {
        while !Task.isCancelled {
            if let value = try? await environment.api.get(P4Route.rearFogStrobeStats) {
                stats = value
                if errorText != nil, value.objectValue?["ok"]?.boolValue == true {
                    errorText = nil
                }
            }
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func start() async {
        guard !busy else { return }
        busy = true
        errorText = nil
        Haptics.impact()
        do {
            let value = try await environment.api.post(P4Route.rearFogStrobeStart)
            stats = value
            Haptics.success()
        } catch {
            // 409：已在运行，或还没收到整车 0x273
            errorText = templateValid
                ? L10n.t("无法开始：上一次爆闪还没结束，请先停止。", "Cannot start: the previous run is still active.")
                : L10n.t("无法开始：还没收到整车 0x273 帧（车辆需上电，车身总线在线）。",
                         "Cannot start: no 0x273 frame from the car yet.")
            Haptics.error()
        }
        busy = false
    }

    private func stop() async {
        guard !busy else { return }
        busy = true
        Haptics.impact()
        if let value = try? await environment.api.post(P4Route.rearFogStrobeStop) {
            stats = value
            Haptics.success()
        } else {
            errorText = L10n.t("停止请求发送失败，请重试。", "Failed to send the stop request.")
            Haptics.error()
        }
        busy = false
    }
}
