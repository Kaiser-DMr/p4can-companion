# SwiftPieces MCP 接入与「功能」页改造

> 版本：v2.8 / build 19 · 2026-11-18
> MCP 端点：`https://swiftpieces.com/api/mcp`（streamable-http，无需鉴权）
> 组件文件：`P4CANCompanion/SwiftPieces/Inputs/FilterRail.swift`

## 1. MCP 配置

已写入 `~/.workbuddy/mcp.json`（原文件已备份为 `mcp.json.bak-*`）：

```json
"swiftpieces": {
  "url": "https://swiftpieces.com/api/mcp",
  "transport": "streamable-http"
}
```

服务信息（`initialize` 握手返回）：

| 项 | 值 |
|---|---|
| serverInfo | `swiftpieces` 0.2.0 |
| protocolVersion | 2025-06-18 |
| 能力 | tools / prompts / resources |
| 工具 | `get_design_skill`、`search_pieces`、`search_blocks`、`get_piece`、`install_piece`、`list_categories`、`get_liquid_glass_guide` |
| Pro 端点 | `https://pro.swiftpieces.com/api/mcp`（含 blocks / screens / themes，本次未使用） |

**激活方式**：新 MCP 不会自动生效。打开 WorkBuddy 的连接器管理页 → 右上角自定义连接器 → 对 `swiftpieces` 点「信任」，之后它的 7 个工具就会出现在会话里，可直接让我调用。

## 2. 它的工作方法（get_design_skill 摘要）

1. **先研究再画**：先看项目已有组件 → 再看组件库 → 再看真实 App，抽「骨架」而不是抄像素；
2. **平台基线**：SwiftUI + Swift 6、`@Observable`、`NavigationStack`、`.task`、SF Symbols、`.sensoryFeedback`；
3. **原生保真 12 条**：语义色双主题、优先系统控件、单一图标族、字体梯度（禁止 `.font(.system(size:))`）、连续圆角、单一阴影层级、8pt 节奏、安全区、标题归导航栏、触觉作标点、按产品格式化数字、根视图可滚动。

这次改造严格按第 3 条走：**没有替换系统 Toggle/Slider/Picker**，只把「分类筛选」这一处自定义控件换成库里的成熟实现。

## 3. 为什么选 FilterRail

库里免费组件 14 类，与「功能」页相关的候选：

| 组件 | 判断 |
|---|---|
| **FilterRail**（inputs） | ✅ 采用：横向玻璃胶囊 + 计数 + 单选指示球，正是分类筛选要做的事 |
| GlassSegments（glass） | ❌ 等宽分段，5 个中文分类会被压到 0.8 缩放并截断 |
| SelectMenu（controls） | ❌ 变成「点开菜单选分类」，多一步操作 |
| LiquidSwitch（controls） | ❌ 详情页的开关继续用系统 Toggle（HIG） |
| ReorderList / WalletStack / ParallaxCard | ❌ 与筛选/列表无关 |

## 4. 改了什么

| 位置 | 之前 | 现在 |
|---|---|---|
| 分类筛选 | 手写 `Capsule` 胶囊 + 自定义选中色，横向滚动，选中项手动 `scrollTo` | `FilterRail`：玻璃胶囊 + 计数徽标 + 蓝色玻璃指示球；单选中自动把选中项滚到中间；左右缘自带渐隐 |
| 交互 | 点击切换，`Haptics.impact()` | 点击 / 拖动皆可；组件内置 `.sensoryFeedback(.selection)`；选中态由 `Set<String>` 绑定驱动 |
| 视觉 | 选中项纯蓝填充、白字 | 半透明玻璃球指示，文字在球边缘「 handing over」处换色 |
| 兼容 | — | 深色模式自动适配；`.accessibilityElement` + 选中 traits 由组件提供 |

代码接线（FeaturesView）：

```swift
FilterRail(
    options: ["全部"] + FeatureModule.Section.allCases.map(\.rawValue),
    selection: Binding(
        get: { selectedSection.map { [$0.rawValue] } ?? ["全部"] },
        set: { newValue in /* "全部" → nil，其余 → Section */ }
    ),
    counts: categoryCounts,                    // ["全部": 19, "驾驶辅助": 6, ...]
    style: FilterRail.Style(indicator: .p4Info, onIndicator: .white, chipHeight: 36)
)
```

保留的原有能力：搜索时隐藏分类条、搜索空态引导、分组标题与 19 个模块、详情页全部逻辑。

## 4.1 间距修正（v2.9）

FilterRail 的胶囊间距来自内部 token `PieceLiquid.apart = 26`（它同时要大于 `merge = 20`，否则胶囊会"粘连"）。
26pt 在 iPhone 上明显偏松，按反馈调整为：

```swift
static let merge: CGFloat = 12   // 原 20
static let apart: CGFloat = 18   // 原 26
```

18 > 12 仍保留"彼此独立、指示球穿过时才合并"的液态语义，视觉上紧凑了一档，第 4 个胶囊会自然露在右缘，滑动提示也更明确。

## 4.2 液态玻璃表面（v2.9，按 get_liquid_glass_guide）

新增 `P4CANCompanion/UI/GlassSurface.swift`：

```swift
if #available(iOS 26.0, *), !reduceTransparency {
    content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
} else {
    content.background(Color.p4Card, in: RoundedRectangle(...))
           .overlay(RoundedRectangle(...).strokeBorder(...))
}
```

遵循规则：`#available` 门禁 + Material 回退、尊重「降低透明度」、只用 `glassEffect(_:in:)` 与 `Glass.regular`。

落地两处：功能页搜索框、详情页说明卡。平坦浅灰底上玻璃本就克制，所以观感变化不大——这是 iOS 26 的预期行为，不是没生效。

## 5. 许可

`FilterRail.swift` 头部保留 MIT + **Commons Clause** 声明：可用于 App（含商业），但不得单独售卖/再分发组件本身。文件原样保留，未删除版权头。

## 6. 验证

| 场景 | 结果 |
|---|---|
| 全部（默认） | 19 个模块，4 个分组，指示球在「全部」 |
| 预选「实验室功能」 | 轨道自动滚动使选中项居中，列表 6 项，摘要「实验室功能 · 6 个模块」 |
| 搜索「限速」 | 分类条隐藏，2 条结果，清除按钮可用 |
| 深色模式 | 玻璃胶囊为深灰、文字浅色，选中蓝球白字，对比度正常 |
| 编译 | 三配置均 BUILD SUCCEEDED（iOS Debug / iOS Release / macCatalyst Release） |

截图：`build/screenshots/sp-01-features-lab.png`、`sp-02-features-dark.png`、`sp-03-search.png`。

## 7. 还能继续用它的什么

- `get_liquid_glass_guide`：iOS 26 的 `glassEffect` API 校验（下一步做玻璃卡片/工具栏时用）
- `search_blocks`：settings/dashboard 类整段屏幕（多为 Pro，免费为 0）
- `install_piece`：返回「路径 + 内容」，直接落到 `P4CANCompanion/SwiftPieces/<类目>/`，Xcode 16 同步组会自动纳管，无需改 pbxproj
