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
| 胶囊 Tab | 三项：**分析**、**对话**、**设置**；选中填充主色或主色描边 |
| 主按钮 | 主色底 + 深色字；`borderedProminent` 需与 AccentColor 一致 |
| 列表行 | `List` + `NavigationLink`，分组 Section |
| 空状态 | 简短说明 + 可选主按钮，语气轻松 |

## 动效

轻量、与交互反馈一致；手表端宠物动画以 Watch 工程为准，iOS 避免抢戏。

## 提醒：调度语义（产品/工程对齐）

- **日历重复**（`UNCalendarNotificationTrigger`）：在指定 **钟点**（及可选星期）触发，例如「每天 9:00」。
- **固定间隔**（`UNTimeIntervalNotificationTrigger`）：从 **保存/启用后** 起每隔 N 秒重复，**不是**「从当天 8:00 起每 2 小时」的墙钟节奏。UI 文案必须向用户说明，避免与「闹钟式」混淆。

---

文档版本：与仓库 `BolaTheme` / `AccentColor` 同步迭代。
