# BolaBola 设计核心（跨端）

用于统一 iPhone、Apple Watch 及后续扩展的视觉与组件语言。实现细节以各端代码中的 **DesignTokens**（如 iOS `BolaTheme`）为准。

## 品牌色

| 名称 | 值 | 用途 |
|------|-----|------|
| **主色 Accent** | `#E5FF00`（sRGB） | 主按钮填充、Tab 选中态、关键描边与高亮、对话中用户气泡点缀 |
| **表面 Surface** | `#1C1C1E`（浅色模式下可与系统 `secondarySystemBackground` 互换） | 卡片底、胶囊 Tab 未强调区域 |
| **正文** | 系统 `Label` / `primary` | 标题与正文 |
| **次要** | 系统 `secondary` | 说明、辅助信息 |

**注意**：主色为高亮黄绿，**不要**用于小字号正文与主色底上的文字（对比度不足）。主按钮上建议使用 **深色文字**（如 `.black` 或 `.primary` 在深色胶囊上按实际对比选择）。

## 语义色

成功 / 警告 / 错误优先使用 **系统语义色**（`Color.green`、`Color.orange`、`Color.red`），必要时在 `BolaTheme` 中再包一层以便深色模式一致。

## 圆角与间距

| Token | 建议值 |
|--------|--------|
| 卡片圆角 | `16`–`20`，`RoundedRectangle(cornerRadius:style: .continuous)` |
| 胶囊 Tab / 大按钮 | 全圆角（`Capsule()`） |
| 区块垂直间距 | `16` / `24` |
| 页面水平内边距 | `20`（随 `safeArea` 调整） |

## 字体

- 中文与西文均使用 **系统动态字体**（`.largeTitle` / `.title2` / `.headline` / `.body` / `.caption`）。
- 数值展示可用 `.monospacedDigit()`。

## 组件约定

| 组件 | 行为 |
|------|------|
| 主 Tab（iPhone） | 图库（Lowe's/LTK）式 **一行**：**`ZStack`** 换页 + **`safeAreaInset`** 内 **`HStack`**（**`IOSCapsuleTabBar`** + 对话 **`Button`**）。**不用** `TabView` + **`tabViewBottomAccessory`**：附件在常规 Tab 高度下在栏 **上方**，易呈「上下两条」。对话钮 iOS 26+ **[`ButtonStyle.glass`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass)**；胶囊用 `glassEffect` 见 [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)。**`.tint(BolaTheme.accent)`** 作用于选中态。 |
| 主按钮 | 主色底 + 深色字；`borderedProminent` 需与 AccentColor 一致 |
| 列表行 | `List` + `NavigationLink`，分组 Section |
| 空状态 | 简短说明 + 可选主按钮，语气轻松 |

## 动效

轻量、与交互反馈一致；手表端宠物动画以 Watch 工程为准，iOS 避免抢戏。

### iOS：液态玻璃与底栏（实现备忘，与代码一致）

以下为实现「底栏液态玻璃」与「内容区贴底滚动时的柔和边缘」的**当前约定**（以 iOS 26+ 系统能力为准；低版本无对应 API 时自动回退）。

1. **底栏：一行 + Liquid Glass**  
   - [新设计图库](https://developer.apple.com/cn/design/new-design-gallery/) 展示的系统 App **视觉**（标签栏 + 侧旁圆形操作）在 SwiftUI 若用 **`tabViewBottomAccessory`**，见 [Discussion](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:))：常规 Tab 高度下附件在栏 **上方**，易呈 **两行**。要 **静止态即一行**，用 **`safeAreaInset` + `HStack`**（[`IOSCapsuleTabBar`](../BolaBola%20iOS/Features/Home/IOSCapsuleTabBar.swift) + **`ButtonStyle.glass`**），根视图为 **`ZStack`**（无系统 `TabView` 底栏）。  
   - [Landmarks](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass) / [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) 中的 **`glassEffect`**、**`ButtonStyle.glass`** 仍适用于自定义胶囊与对话钮。  
   - **代码位置**：[`IOSRootView.swift`](../BolaBola%20iOS/App/IOSRootView.swift)。

2. **主 Tab 内容滚动：滚动边缘液态口袋（与底栏衔接）**  
   - **iOS 26+**：根级或主列 **`ScrollView`** 使用 **`scrollEdgeEffectStyle`**（[`bolaRootTabScrollEdgeStyles()`](../BolaBola%20iOS/Design/IOSGlassChrome.swift)），与 **浮动自定义底栏** + 安全区配套。  
   - **参考**：[`scrollEdgeEffectStyle(_:for:)`](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:))。  
   - **代码位置**：[`IOSGlassChrome.swift`](../BolaBola%20iOS/Design/IOSGlassChrome.swift) 内 **`bolaScrollEdgeLiquidGlassMainContent()`**。

3. **历史**  
   - 曾用 **`TabView` + `tabViewBottomAccessory`**；附件与 Tab **两行**叠放，改回 **单行 `safeAreaInset` + `IOSCapsuleTabBar`**。

### iOS：生活 Tab 全屏底与顶栏分段（页面原则，必守）

适用于根级仍为系统 **`TabView`** + 液态玻璃底栏时的 **生活页内壳**（[`IOSLifeContainerView`](../BolaBola%20iOS/Features/Life/IOSLifeContainerView.swift)）。违反时易在 **系统底栏上方** 多出一条 **模糊带 / 假安全区**，看起来像「bar 下面还有一层」。

| 原则 | 做法 |
|------|------|
| **全屏铺底** | 生活页背景层（分组灰 + 顶渐变 + 呼吸球）使用 **`ignoresSafeArea(edges: [.top, .bottom])`**，与页面视觉一致，顶底连续。 |
| **「生活 / 时光」分段与横滑** | **不要**内层 **`TabView` + `.page`**，**不要** **`UIPageViewController`** 桥接（易叠安全区）。横滑用 **横向 `ScrollView` + `scrollTargetBehavior(.paging)` + `scrollPosition(id:)`**（`containerRelativeFrame` 两页），与 [`IOSLifeSegmentLarge`](../BolaBola%20iOS/Features/Life/IOSLifeToolbarCenter.swift) 同绑 `lifeSegment`。竖向列表 **`scrollIndicators(.hidden)`**，横向分页 **`showsIndicators: false`**。 |
| **底球位置** | 底部氛围球 overlay 使用 **`offset(y: 200 − safeAreaInsets.bottom)`**（与 GitHub `main` 一致），勿随意叠 `scaleEffect` 与过大 `offset`。 |

横滑与顶栏标题共用 `lifeSegment` / `horizontalPageID` 同步。

## 提醒：调度语义（产品/工程对齐）

- **日历重复**（`UNCalendarNotificationTrigger`）：在指定 **钟点**（及可选星期）触发，例如「每天 9:00」。
- **固定间隔**（`UNTimeIntervalNotificationTrigger`）：从 **保存/启用后** 起每隔 N 秒重复，**不是**「从当天 8:00 起每 2 小时」的墙钟节奏。UI 文案必须向用户说明，避免与「闹钟式」混淆。

---

文档版本：与仓库 `BolaTheme` / `AccentColor` 同步迭代。
