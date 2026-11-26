import SwiftUI

/// 系统 → 车辆外观：指定状态页显示的车型、版本、车漆与轮毂，预览三个视角。
struct VehicleAppearanceView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(VehicleAppearanceKeys.generation) private var generationID = ""
    @AppStorage(VehicleAppearanceKeys.trim) private var trimCode = ""
    @AppStorage(VehicleAppearanceKeys.paint) private var paintCode = ""
    @AppStorage(VehicleAppearanceKeys.wheel) private var wheelCode = ""
    @State private var previewAngle: VehicleAngle = .front

    /// 设备车型对应的配置器车型（跟随设备时使用）
    private var deviceGeneration: VehicleGeneration {
        let id = VehicleBodyStyle.resolve(profileID: environment.profileID, name: environment.profileName).generationID
        return VehicleCatalog.generation(id: id) ?? VehicleCatalog.generations[0]
    }

    var body: some View {
        let device = deviceGeneration
        let current = VehicleCatalog.resolve(generationID: generationID, trim: trimCode, paint: paintCode,
                                             wheel: wheelCode, deviceGenerationID: device.id)
        Form {
            Section {
                VehicleHeroImage(appearance: current, angle: previewAngle)
                    .frame(height: 190)
                    .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 4, trailing: 8))
                Picker(L10n.t("视角", "View"), selection: $previewAngle) {
                    Text(L10n.t("斜前方 · P", "Front · P")).tag(VehicleAngle.front)
                    Text(L10n.t("侧面 · D/N", "Side · D/N")).tag(VehicleAngle.side)
                    Text(L10n.t("斜后方 · R", "Rear · R")).tag(VehicleAngle.rear)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(L10n.t("状态页按挡位切换视角：P 挡斜前方，D / N 挡侧面，R 挡斜后方。",
                            "The status page follows the gear: P shows the front, D / N the side, R the rear."))
            }

            Section {
                Picker(L10n.t("车型", "Model"), selection: $generationID) {
                    Text(L10n.t("跟随设备（\(device.zh)）", "Follow device (\(device.en))")).tag("")
                    ForEach(VehicleCatalog.generations) { generation in
                        Text(L10n.t(generation.zh, generation.en)).tag(generation.id)
                    }
                }
                Picker(L10n.t("版本", "Trim"), selection: Binding(
                    get: { current.trim.code },
                    set: { trimCode = $0 }
                )) {
                    ForEach(current.generation.trims) { trim in
                        Text(L10n.t(trim.zh, trim.en)).tag(trim.code)
                    }
                }
            } footer: {
                Text(L10n.t("跟随设备时按固件车型显示；Model S/X 固件车型不区分 S 与 X，请在这里手动选择。",
                            "Following the device uses the firmware vehicle profile. The firmware does not tell Model S from Model X, so pick it here."))
            }

            Section(L10n.t("车漆", "Paint")) {
                ForEach(current.trim.paints) { paint in
                    Button {
                        paintCode = paint.code
                    } label: {
                        HStack(spacing: Theme.Icon.gap) {
                            Circle()
                                .fill(Color(hex: paint.swatch ?? 0x888888))
                                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                                .frame(width: 26, height: 26)
                            Text(L10n.t(paint.zh, paint.en))
                                .foregroundStyle(.primary)
                            Spacer()
                            if paint.code == current.paint.code {
                                Image(systemName: "checkmark").foregroundStyle(Color.p4Accent)
                            }
                        }
                    }
                    .tint(.primary)
                    .accessibilityAddTraits(paint.code == current.paint.code ? .isSelected : [])
                }
            }

            Section {
                ForEach(current.trim.wheels) { wheel in
                    Button {
                        wheelCode = wheel.code
                    } label: {
                        HStack {
                            Text(L10n.t(wheel.zh, wheel.en))
                                .foregroundStyle(.primary)
                            Spacer()
                            if wheel.code == current.wheel.code {
                                Image(systemName: "checkmark").foregroundStyle(Color.p4Accent)
                            }
                        }
                    }
                    .tint(.primary)
                    .accessibilityAddTraits(wheel.code == current.wheel.code ? .isSelected : [])
                }
            } header: {
                Text(L10n.t("轮毂", "Wheels"))
            } footer: {
                Text(L10n.t("车辆图片来自特斯拉官网配置器，首次显示需要联网，之后缓存在本机。",
                            "Vehicle images come from Tesla's online configurator. They need a network connection the first time and are cached on this device."))
            }
        }
        .navigationTitle(L10n.t("车辆外观", "Vehicle Appearance"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
