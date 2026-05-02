# Bola 自定义名字文案扫描清单

Generated: 2026-05-01

## 替换规则

- 用户给宠物起名后，用户可见的宠物称呼优先使用 `CompanionDisplayNameStore.resolved()`。
- 宠物名最多 6 个可见字符；超长输入会截断。
- 品牌名 `BolaBola` 保留。
- 代码类型名、资源名、asset 名、日志 subsystem、枚举 case 保留。
- onboarding 中“给 Bola 起名”之前的品牌/角色介绍暂保留 `Bola`；起名完成后的主体验使用自定义名字。

## 已接入自定义名字

| 模块 | 位置 | 状态 | 说明 |
| --- | --- | --- | --- |
| 存储 | `Shared/Companion/CompanionDisplayNameStore.swift` | 已替换 | 统一读取、保存、清空、6 字截断 |
| Onboarding | `BolaBola iOS/Features/Onboarding/IOSOnboardingView.swift` | 已替换 | 完成 onboarding 时写入正式宠物名 |
| 设置 | `BolaBola iOS/Features/Settings/IOSSettingsView.swift` | 已替换 | 新增 Bola 设置 / 名字 |
| iOS 根导航 | `BolaBola iOS/App/IOSRootView.swift` | 已替换 | “和 X 聊天”“X 的空间” |
| iOS 聊天 | `BolaBola iOS/Features/Chat/IOSChatTestSection.swift` | 已替换 | 助手角色名、锁定/未配置提示 |
| watch 聊天历史 | `BolaBola Watch App/Views/WatchChatHistoryView.swift` | 已替换 | 助手角色名 |
| watch 面板 | `BolaBola Watch App/Views/WatchDrawerAndChrome.swift` | 已替换 | 对话记录副标题、默认提醒文案 |
| LLM 对话 | `Shared/LLM/ConversationService.swift` | 已替换 | system prompt、默认提醒标题 |
| 日记提取 | `Shared/Diary/DiaryIntentParser.swift` | 已替换 | 生活记忆提取提示词 |
| 默认提醒 | `Shared/Reminders/ReminderTemplates.swift` / `ReminderBootstrap.swift` | 已替换 | 新建模板和首次默认提醒 |
| 每日总结通知 | `Shared/Digest/DailyDigestUNScheduler.swift` / `DailyDigestRefresh.swift` | 已替换 | 通知标题、兜底正文、生成提示词 |
| iOS 时光空态 | `BolaBola iOS/Features/Life/IOSLifeTimePageView.swift` | 已替换 | 空态引导“和 X 聊聊今天” |

## 保留 Bola / BolaBola

| 模块 | 示例 | 原因 |
| --- | --- | --- |
| 品牌介绍 | `BolaBola 是什么？` | 品牌名 |
| 代码符号 | `BolaWCSessionCoordinator`、`BolaReminder` | 类型名稳定性 |
| 资源名 | `BolaLogo`、`RhythmBola_*` | asset 名 |
| 贴纸枚举 | `stickerBola` | 内部标识 |
| 日志 | `com.GathXRTeam.BolaBola` | subsystem / bundle 语境 |
| onboarding 前置介绍 | “欢迎来到 BolaBola”“和 Bola 一起...” | 用户尚未完成起名 |

## 后续确认

| 模块 | 位置 | 建议 |
| --- | --- | --- |
| 帮助中心 | `BolaBola iOS/Features/HelpCenter/HelpCenterContent.swift` | 大部分是产品说明，暂保留；后续可在“认识 Bola”文章里按显示名做局部动态化 |
| 特殊动画图鉴 | `Shared/Growth/SpecialAnimationUnlockSystem.swift` | 描述里可后续动态替换，但当前是静态成就说明 |
| 天气/生活卡片历史数据 | `WeatherDiaryRecorder`、既有 `LifeRecordCard` | 新生成内容可使用新名字；旧记录不迁移 |
