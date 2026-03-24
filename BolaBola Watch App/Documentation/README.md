# Bola（Watch）文档索引

设计说明、规则与 PRD 均集中在本目录，避免与源码、资源混在同一层级。

| 文档 | 说明 |
|------|------|
| [PRD_v1.md](PRD_v1.md) | 产品需求草案 |
| [companion_value_rules.md](companion_value_rules.md) | 陪伴值计分与扣分规则 |
| [state_machine_list.md](state_machine_list.md) | 状态机、陪伴值→默认动画 |
| [animation_list.md](animation_list.md) | 动画资源清单 |
| [bola_dialogue_rules.md](bola_dialogue_rules.md) | 台词触发、节流、台词池 |
| [tap_interaction_rules.md](tap_interaction_rules.md) | 点击交互与连击生气 |
| [health_reminders_platform.md](health_reminders_platform.md) | 本地通知、HealthKit、平台限制 |

**代码引用**：在 Swift 注释中优先写 `Documentation/<文件名>`，便于在仓库内搜索。

**Watch 源码结构（节选）**：`ContentView.swift` 为主界面与 `PetViewModel`；`PetAnimation.swift` 为动画类型、`AnimationScale`、帧资源与 `PetAnimationView` 等视图。

### 运行与 WatchConnectivity（调试）

- 使用 **BolaBola**（iOS）Scheme、目标选 **已配对的 iPhone + Apple Watch** 时，共享 Scheme 内已带 **RemoteRunnable**，Xcode 会随 iPhone 一并安装/启动表端，有利于 `isWatchAppInstalled` 尽快变为 `true`。
- 若长期只用 **BolaBola Watch App** Scheme 单独装表，手机侧可能仍报 `watchAppInstalled=false`，属系统常见现象；可改回主 Scheme 跑一轮或到「Watch」App 里确认表端已安装。
- 表端 `WCSession` 在 `BolaBolaApp.init()` 即激活（与 iOS `IOSAppDelegate` 尽早 `activate()` 对齐），避免 UI 未起时 `didReceiveUserInfo` 无法经 delegate 处理。
