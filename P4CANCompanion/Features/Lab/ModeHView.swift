import SwiftUI

/// LAB → Mode H 调参：对应固件网页 `panelNagModeH` / `panelNagModeH` 的高级参数。
///
/// 与网页契约一致：13 个参数必须**一次提交**到 `/api/nag/h-profile/update`；
/// 停车行为单独走 `/api/nag/update?modeHStopBehavior=`。
struct ModeHView: View {
    @EnvironmentObject private var environment: AppEnvironment

    // 可编辑参数（首次从设备读取，之后不覆盖用户正在调的值）
    @State private var peakMin = 1.0
    @State private var peakMax = 2.4
    @State private var waitMin = 0.8
    @State private var waitMax = 2.0
    @State private var refractoryMin = 0.5
    @State private var refractoryMax = 1.5
    @State private var carrierMin = 0.10
    @State private var carrierMax = 0.60
    @State private var ho1 = 0.40
    @State private var ho2 = 2.00
    @State private var rescueEnabled = true
    @State private var rescueDelay = 0.5
    @State private var hoPolicy = 2
    @State private var stopBehavior = 1

    @State private var formLoaded = false
    @State private var busy = false
    @State private var confirmsReset = false

    @State private var stats: P4JSON?
    @State private var loadError: String?

    private var object: [String: P4JSON] { stats?.objectValue ?? [:] }

    var body: some View {
        List {
            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.p4Err)
                }
            }

            Section {
                sliderRow(L10n.t("主峰值下限", "Primary peak min"), value: $peakMin,
                          range: 1...3, step: 0.05, unit: "Nm")
                sliderRow(L10n.t("主峰值上限", "Primary peak max"), value: $peakMax,
                          range: 1...3, step: 0.05, unit: "Nm")
            } header: {
                Label(L10n.t("主事件峰值", "Primary peak"), systemImage: "waveform.path")
            } footer: {
                Text(L10n.t("每次合格的原厂 0x370 接收都会在区间内重新抽取峰值；80% 为负向、20% 为正向。",
                            "Every eligible stock 0x370 RX draws a new peak in range; 80% negative, 20% positive."))
            }

            Section {
                sliderRow(L10n.t("等待下限", "Wait min"), value: $waitMin,
                          range: 0.3...5, step: 0.1, unit: "s")
                sliderRow(L10n.t("等待上限", "Wait max"), value: $waitMax,
                          range: 0.3...5, step: 0.1, unit: "s")
                sliderRow(L10n.t("不应期下限", "Refractory min"), value: $refractoryMin,
                          range: 0.3...2.5, step: 0.1, unit: "s")
                sliderRow(L10n.t("不应期上限", "Refractory max"), value: $refractoryMax,
                          range: 0.3...2.5, step: 0.1, unit: "s")
            } header: {
                Label(L10n.t("等待与不应期", "Wait & refractory"), systemImage: "timer")
            }

            Section {
                sliderRow(L10n.t("载波下限", "Carrier min"), value: $carrierMin,
                          range: 0.1...0.8, step: 0.05, unit: "Nm")
                sliderRow(L10n.t("载波上限", "Carrier max"), value: $carrierMax,
                          range: 0.1...0.8, step: 0.05, unit: "Nm")
            } header: {
                Label(L10n.t("反向载波", "Opposite carrier"), systemImage: "arrow.left.arrow.right")
            } footer: {
                Text(L10n.t("非零原厂扭矩会镜像到反号并叠加载波；原厂 ≤ 0.05 Nm 直接透传。",
                            "Non-zero stock torque is mirrored to the opposite sign plus carrier; stock ≤ 0.05 Nm passes through."))
            }

            Section {
                Picker(L10n.t("Hands-On 策略", "Hands-On policy"), selection: $hoPolicy) {
                    Text(L10n.t("始终 HO=1", "Always HO=1")).tag(0)
                    Text(L10n.t("阈值 HO=1", "Threshold HO=1")).tag(1)
                    Text(L10n.t("分级 HO=1 / 2", "Tiered HO=1 / 2")).tag(2)
                }
                .pickerStyle(.menu)
                sliderRow(L10n.t("HO=1 阈值", "HO=1 threshold"), value: $ho1,
                          range: 0.1...3, step: 0.05, unit: "Nm")
                sliderRow(L10n.t("HO=2 阈值", "HO=2 threshold"), value: $ho2,
                          range: 0.1...3, step: 0.05, unit: "Nm")
            } header: {
                Label(L10n.t("Hands-On 覆盖", "Hands-On policy"), systemImage: "hand.raised")
            } footer: {
                Text(L10n.t("固件会完整覆盖 2 位 HO 字段，生成值不会超过 HO=2。阈值模式下低于 HO=1 阈值时保留原厂 HO。",
                            "The firmware overwrites the full 2-bit HO field and never generates HO=3. Below the HO=1 threshold the stock HO field is kept."))
            }

            Section {
                Toggle(isOn: $rescueEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("视觉预警救援", "Visual warning rescue"))
                        Text(L10n.t("DAS 视觉预警会延迟触发一次主峰值", "DAS visual warning starts a delayed primary peak"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                sliderRow(L10n.t("救援延迟", "Rescue delay"), value: $rescueDelay,
                          range: 0...2, step: 0.1, unit: "s")
                    .disabled(!rescueEnabled)
            } header: {
                Label(L10n.t("视觉救援", "Visual rescue"), systemImage: "eye.trianglebadge.exclamationmark")
            }

            Section {
                Picker(L10n.t("停车行为", "Stop behavior"), selection: $stopBehavior) {
                    Text(L10n.t("STOCK CARRIER · 保留原厂", "STOCK CARRIER")).tag(1)
                    Text(L10n.t("HARD PAUSE · 0 发送", "HARD PAUSE · 0-TX")).tag(0)
                }
                .pickerStyle(.menu)
            } header: {
                Label(L10n.t("停车行为", "Stop behavior"), systemImage: "parkingsign")
            } footer: {
                Text(L10n.t("停车状态只暂停事件引擎；STOCK CARRIER 会保留原厂扭矩与 HO，只推进计数与校验和。速度失效或确认移动时始终硬暂停。",
                            "STOPPED only pauses the event engine. STOCK CARRIER preserves stock torque and HO. Speed-stale and move-confirming states always hard-pause."))
            }

            Section {
                Button {
                    apply()
                } label: {
                    Label(L10n.t("应用 Mode H 调参", "Apply Mode H Tuning"), systemImage: "checkmark.circle")
                }
                .disabled(!formLoaded || busy || environment.isBusy)

                Button {
                    loadForm(force: true)
                } label: {
                    Label(L10n.t("重新从设备读取", "Reload from device"), systemImage: "arrow.clockwise")
                }
                .disabled(busy)

                Button(role: .destructive) {
                    confirmsReset = true
                } label: {
                    Label(L10n.t("重置当前配置", "Reset Current Profile"), systemImage: "arrow.counterclockwise")
                }
                .disabled(busy)
            } footer: {
                Text(L10n.t("参数保存在设备端；重置会恢复该车型的默认波形。",
                            "Parameters are stored on the device. Reset restores the profile defaults."))
            }

            liveSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.t("Mode H 调参", "Mode H Tuning"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .task { await poll() }
        .confirmationDialog(
            L10n.t("重置 Mode H 当前配置？", "Reset the current Mode H profile?"),
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button(L10n.t("确认重置", "Reset"), role: .destructive) {
                Task {
                    busy = true
                    await environment.command(L10n.t("重置 Mode H", "Reset Mode H"),
                                              path: P4Route.nagHProfileReset)
                    busy = false
                    formLoaded = false
                    await load()
                }
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        }
    }

    // MARK: - 实时引擎

    private var liveSection: some View {
        Section {
            if stats == nil {
                SkeletonRows(count: 4)
            } else {
                MetricRow(key: "phase", value: object["phase"] ?? .null)
                MetricRow(key: "eventType", value: object["eventType"] ?? .null)
                MetricRow(key: "activeEventPeakNm", value: object["activeEventPeakNm"] ?? .null)
                MetricRow(key: "outputNm", value: object["outputNm"] ?? .null)
                MetricRow(key: "carrierSampleNm", value: object["carrierSampleNm"] ?? .null)
                MetricRow(key: "stopCarrierActive", value: object["stopCarrierActive"] ?? .null)
            }
        } header: {
            Label(L10n.t("实时引擎", "Live engine"), systemImage: "waveform.path.ecg")
        } footer: {
            Text(L10n.t("只读监视当前 Phase / 事件类型 / 输出扭矩；数据来自 /api/nag/h-profile/stats。",
                        "Read-only monitor of phase, event type and output torque from /api/nag/h-profile/stats."))
        }
    }

    // MARK: - 行

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text("\(format(value.wrappedValue)) \(unit)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel("\(title)，单位\(unit)")
                .accessibilityValue("\(format(value.wrappedValue)) \(unit)")
        }
        .padding(.vertical, 2)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    // MARK: - 读写

    private func poll() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: .milliseconds(1200))
        }
    }

    private func load() async {
        do {
            let value = try await environment.api.get(P4Route.nagHProfileStats)
            stats = value
            loadError = nil
            if !formLoaded {
                loadForm(force: false)
                if let config = try? await environment.api.get(P4Route.nagConfig),
                   let stop = config.objectValue?["modeHStopBehavior"]?.intValue {
                    stopBehavior = Int(stop)
                }
                formLoaded = true
            }
        } catch {
            loadError = AppEnvironment.friendly(error)
        }
    }

    /// `force` = 丢弃本地编辑，重新按设备值填充。
    private func loadForm(force: Bool) {
        guard force || !formLoaded else { return }
        guard let object = stats?.objectValue else { return }
        if let value = object["peakMinNm"]?.doubleValue { peakMin = value }
        if let value = object["peakMaxNm"]?.doubleValue { peakMax = value }
        if let value = object["waitMinMs"]?.doubleValue { waitMin = value / 1000 }
        if let value = object["waitMaxMs"]?.doubleValue { waitMax = value / 1000 }
        if let value = object["refractoryMinMs"]?.doubleValue { refractoryMin = value / 1000 }
        if let value = object["refractoryMaxMs"]?.doubleValue { refractoryMax = value / 1000 }
        if let value = object["carrierMinNm"]?.doubleValue { carrierMin = value }
        if let value = object["carrierMaxNm"]?.doubleValue { carrierMax = value }
        if let value = object["ho1ThresholdNm"]?.doubleValue { ho1 = value }
        if let value = object["ho2ThresholdNm"]?.doubleValue { ho2 = value }
        if let value = object["hoPolicy"]?.intValue { hoPolicy = Int(value) }
        if let value = object["visualRescueEnabled"]?.boolValue { rescueEnabled = value }
        if let value = object["visualRescueDelayMs"]?.doubleValue { rescueDelay = value / 1000 }
        formLoaded = true
    }

    private func apply() {
        guard peakMin <= peakMax else {
            environment.toast = P4Toast(message: L10n.t("主峰值下限不能大于上限", "Peak min cannot exceed max"), style: .failure)
            return
        }
        guard waitMin <= waitMax else {
            environment.toast = P4Toast(message: L10n.t("等待下限不能大于上限", "Wait min cannot exceed max"), style: .failure)
            return
        }
        guard refractoryMin <= refractoryMax else {
            environment.toast = P4Toast(message: L10n.t("不应期下限不能大于上限", "Refractory min cannot exceed max"), style: .failure)
            return
        }
        guard carrierMin <= carrierMax else {
            environment.toast = P4Toast(message: L10n.t("载波下限不能大于上限", "Carrier min cannot exceed max"), style: .failure)
            return
        }

        let query = [
            P4Param("peakMinNm", String(format: "%.2f", peakMin)),
            P4Param("peakMaxNm", String(format: "%.2f", peakMax)),
            P4Param("waitMinMs", String(Int((waitMin * 1000).rounded()))),
            P4Param("waitMaxMs", String(Int((waitMax * 1000).rounded()))),
            P4Param("refractoryMinMs", String(Int((refractoryMin * 1000).rounded()))),
            P4Param("refractoryMaxMs", String(Int((refractoryMax * 1000).rounded()))),
            P4Param("carrierMinNm", String(format: "%.2f", carrierMin)),
            P4Param("carrierMaxNm", String(format: "%.2f", carrierMax)),
            P4Param("hoPolicy", String(hoPolicy)),
            P4Param("ho1ThresholdNm", String(format: "%.2f", ho1)),
            P4Param("ho2ThresholdNm", String(format: "%.2f", ho2)),
            P4Param("visualRescueEnabled", rescueEnabled ? "1" : "0"),
            P4Param("visualRescueDelayMs", String(Int((rescueDelay * 1000).rounded()))),
        ]

        busy = true
        Task {
            await environment.command(L10n.t("Mode H 调参", "Mode H tuning"),
                                      path: P4Route.nagHProfileUpdate, query: query)
            await environment.command(L10n.t("Mode H 停车行为", "Mode H stop behavior"),
                                      path: P4Route.nagUpdate,
                                      query: [P4Param("modeHStopBehavior", String(stopBehavior))])
            busy = false
            await load()
        }
    }
}
