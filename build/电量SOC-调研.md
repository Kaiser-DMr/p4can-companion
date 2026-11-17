# 能不能从 P4-CAN 拿到车辆电量（SOC）？

## 结论

**现有固件拿不到。** 它不是"接口没暴露"，而是**固件里根本没有解析电量**：

- 全仓库（`web_api.h` / `can_*.h` / `vehicle_logic.h` / `dashboard_source.html`）搜索
  `battery` / `soc` / `stateOfCharge` / `range` / `kwh` / `charging`，**没有任何电池相关解析**；
  命中的 `soc` 只有 ESP32 的 `soc/soc_caps.h` 头文件，`Ms` 是毫秒变量名。
- 设备解码的 CAN ID 全部是车身/底盘/驾驶辅助信号：`0x399` 转向、`0x334` AP、
  `0x3F8` ULC、`0x3FD`、`0x118`、`0x370`、`0x24A`、`0x238`、`0x293`、`0x249`、`0x186`、
  `0x239`（车道模型）、`0x3C2`、`0x39B`、`0x247` …，**没有 BMS / 电池包相关 ID**。
- 网页与 `/api/*` 里也没有电量字段（`/api/snapshot` 的 `nag / blink / summon / cantraffic / r79`
  五组里均无）。

所以 App 端无论怎么改都取不到——**数据源就没有这个值**。

## 硬件层面：不是不能，是没做

设备接的是 X179 的三路 CAN（`pin_config.h`）：

| 通道 | 引脚 | X179 针脚 | 总线 |
|---|---|---|---|
| CAN 1 | GPIO4/5（或 20/21） | 9/10 | BODY / VEHICLE |
| CAN 2 | GPIO2/3（或 22/23） | 13/14 | CHASSIS |
| CAN 3 | GPIO26/27 | 2/3 | PARTY |

电量通常由 BMS 在 **VEHICLE 总线**上广播，而这颗盒子**物理上就接在 VEHICLE 上**（CAN 1）。
也就是说：**帧大概率是能收到的，只是固件没去解析它**。

## 想拿到 SOC，需要三步

### 第 1 步：确认总线上真的有 SOC 帧（不需要改固件）

固件自带「CAN 研究捕获」，RAW 模式会把三路总线的原始帧录下来，导出 CSV：

```bash
# 网页：实验室 → CAN 研究捕获 → 模式 RAW_TRANSITION（或 RAW_AUTO_ALC）→ 开始 → 停 → 导出
# 或直接拉接口：
curl -o capture.csv http://192.168.4.1/api/researchcapture/log.csv
```

CSV 列：`segment_id, …, physical_bus, bus_role, source, tx_ok, id, dlc, raw`
（`id` 形如 `0x2C2`，`raw` 形如 `"44 00 13 88 …"`）

然后用仓库里的探测脚本扫候选字段：

```bash
python3 build/tools/soc_probe.py capture.csv --bus VEHICLE --top 30
```

脚本会按"像不像 SOC"排序（值域 0–100、变化平缓、趋势单调、帧周期稳定）。
**确认方法**：充电前抓一次、充电 10 分钟后再抓一次，候选值应朝同一方向变化。

### 第 2 步：固件加解码（约 30 行）

在 CAN 接收分发处（`can_runtime.h` 的 RX 处理，`researchCaptureOnCanFrame` 同层）加：

```cpp
// 伪代码：确认 ID 后按位解析
if (bus == CAN_BUS_VEHICLE && id == 0x2C2 /* 以第 1 步实测为准 */) {
    uint16_t raw = (uint16_t)data[0] | ((uint16_t)data[1] << 8);
    batterySocDeci = raw;            // 例如 0..1000 表示 0.0..100.0%
    batterySocMs = millis();
}
```

再在两处暴露：

1. `systemStatsToJson()` 或 `homeFastSnapshotToJson()` 加字段：
   `jw.fixed("batterySoc", batterySocDeci, 1);` 或 `jw.u32("batterySoc", soc);`
2. 网页 `dashboard_source.html` 加一行显示（可选）。

### 第 3 步：App 端（**已经做好，等字段**）

`DashboardView` 里已预留电池卡：只要任一端点返回
`batterySoc` / `soc` / `batteryLevel` / `stateOfCharge`（0–100），
以及可选的 `rangeKm` / `batteryRangeKm`，卡片就会自动出现在 KPI 与快捷开关之间；
没有字段就**整卡隐藏**（遵守"不显示默认值"规则）。

演示效果（mock 注入 `batterySoc=68, rangeKm=312`）：`screenshots/soc-demo.png`

## 一句话版本

> 现在拿不到，因为固件没解析电量；但盒子物理上接在 VEHICLE 总线上，
> 用自带的 RAW 捕获 + `soc_probe.py` 就能确认总线上有没有 SOC 帧，
> 找到 ID 后固件加 ~30 行解析，App 侧已经不用再改。
