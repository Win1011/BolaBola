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
