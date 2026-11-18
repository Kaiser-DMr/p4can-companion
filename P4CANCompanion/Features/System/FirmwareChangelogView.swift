import SwiftUI

/// 固件变更记录：刷写前先看这一版改了什么。
///
/// 内容与 `build/firmware-build/刷机与验证.md`、`开发说明-爆闪.md` 对齐；
/// 固件版本号来自 `system/stats.fwVersion`，能对上就在标题上打勾。
struct FirmwareChangelogView: View {
    @EnvironmentObject private var environment: AppEnvironment

    /// 一条变更：版本 + 主题 + 日期 + 要点。
    private struct Entry: Identifiable {
        let id: String
        let version: String
        let title: String
        let date: String
        let notes: [String]
    }

    private var currentFirmware: String {
        environment.systemStats?["fwVersion"]?.stringValue ?? "—"
    }

    private var entries: [Entry] {
        [
            Entry(
                id: "rear-fog",
                version: "v3.29.3 · 后雾灯补丁",
                title: L10n.t("后雾灯爆闪（0x273）", "Rear fog strobe (0x273)"),
                date: "2026-11-18",
                notes: [
                    L10n.t("新增 rear_fog_strobe.h：镜像整车 0x273 后翻转 byte2 bit7 立即回发",
                           "New rear_fog_strobe.h: mirror 0x273 and flip byte2 bit7 on the next frame"),
                    L10n.t("单次最长 30 秒，停止后整车下一帧即恢复触发前状态",
                           "Up to 30 s per run; the car restores the previous state on its next frame"),
                    L10n.t("需要车辆上电、车身总线在线并能持续收到 0x273",
                           "Requires the car powered and 0x273 continuously received"),
                ]
            ),
            Entry(
                id: "headlight",
                version: "v3.29.3 · 前大灯补丁",
                title: L10n.t("前大灯爆闪（0x249）", "Headlight strobe (0x249)"),
                date: "2026-11-18",
                notes: [
                    L10n.t("新增 headlight_strobe.h：0x249 高灯拨杆 PULL/IDLE 交替注入",
                           "New headlight_strobe.h: alternate 0x249 high-beam stalk PULL/IDLE"),
                    L10n.t("次数 1–30、间隔 50–1000 ms 可配；按住拨杆 2.5 秒触发，松开即停",
                           "1–30 flashes at 50–1000 ms; hold the stalk 2.5 s to start, release to stop"),
                    L10n.t("与转向灯注入互斥；CAN 重启（epoch 变化）会自动中止并恢复",
                           "Mutually exclusive with turn-signal injection; aborts and restores on CAN epoch change"),
                ]
            ),
            Entry(
                id: "harness",
                version: "v3.29.3 · 线束字段",
                title: L10n.t("线束与板型自检", "Harness self-check"),
                date: "2026-11-18",
                notes: [
                    L10n.t("/api/system/stats 增加 canHarness / canPins 字段",
                           "/api/system/stats now reports canHarness / canPins"),
                    L10n.t("刷错板型（X179 与标准接线）会表现为两路 CAN 无数据，App 可直接看到引脚表",
                           "Wrong board variant shows up as two dead CAN buses; the app can show the pin table"),
                ]
            ),
            Entry(
                id: "base",
                version: "v3.29.3 · 基准",
                title: L10n.t("基础功能（三路 CAN + 驾驶辅助）", "Base build (3 CAN + driver assist)"),
                date: "2026-11",
                notes: [
                    L10n.t("三路 CAN（BODY / CHASSIS / PARTY）并行收发与健康统计",
                           "Three CAN buses (BODY / CHASSIS / PARTY) with health counters"),
                    L10n.t("NAG / ISA / DMS / 视觉限速 / TLSSC / 自动转向灯 / 变道免确认 / 踏板映射 / 常驻 AP",
                           "NAG / ISA / DMS / vision speed limit / TLSSC / auto blinker / stalk confirm / pedal map / continuous AP"),
                    L10n.t("内嵌 Web 控制台与 /api/* 查询参数接口", "Built-in web console and /api/* query API"),
                ]
            ),
        ]
    }

    private func matchesCurrent(_ entry: Entry) -> Bool {
        guard entry.id != "base" else { return currentFirmware.contains("3.29.3") }
        // 自定义版本串（如 v3.29.3-strobe）无法区分补丁，只有基础版会精确命中。
        return false
    }

    var body: some View {
        List {
            Section {
                LabeledContent(L10n.t("当前固件", "Current firmware"), value: currentFirmware)
                LabeledContent(L10n.t("刷写方式", "Flashing"), value: L10n.t("App 内 OTA（.ino.bin）", "In-app OTA (.ino.bin)"))
            } footer: {
                Text(L10n.t("记录的是固件侧的改动；App 侧的调整见版本说明。刷写前建议先核对版本与 SHA-256。",
                            "Only firmware-side changes are listed. Check the version and SHA-256 before flashing."))
            }

            ForEach(entries) { entry in
                Section {
                    ForEach(Array(entry.notes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(1)) {
                            Circle()
                                .fill(entry.id == "base" ? Color.secondary.opacity(0.4) : Color.accentColor)
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(note)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 1)
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(1)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(entry.version)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Theme.spacing(1))
                        if matchesCurrent(entry) {
                            StatusChip(text: L10n.t("当前", "Current"), systemImage: "checkmark", tone: .ok)
                        }
                        Text(entry.date)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.t("固件变更记录", "Firmware changelog"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.p4Background, for: .navigationBar)
        .scrollContentBackground(.hidden)
        .background(Color.p4Background.ignoresSafeArea())
    }
}
