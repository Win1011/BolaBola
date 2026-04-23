# BolaBola 系统架构文档：Sync / Core State / Companion Value

**生成日期**：2026-04-23
**覆盖范围**：iPhone↔Watch 同步系统、核心状态管理、陪伴值体系
**代码基线**：main 分支

---

## 目录

1. [系统总览](#1-系统总览)
2. [数据持久化层](#2-数据持久化层)
3. [Companion Value（陪伴值）体系](#3-companion-value陪伴值体系)
4. [Core State Management（核心状态管理）](#4-core-state-management核心状态管理)
5. [Sync 系统（iPhone↔Watch 同步）](#5-sync-系统iphonewatch-同步)
6. [NotificationCenter 事件表](#6-notificationcenter-事件表)
7. [关键流程时序](#7-关键流程时序)
8. [附录：变量速查表](#8-附录变量速查表)

---

## 1. 系统总览

### 1.1 架构分层

```
┌─────────────────────────────────────────────────────────┐
│                    UI / View 层                          │
│  Watch: ContentView + PetViewModel                      │
│  iOS: IOSRootView + 各 Tab 子视图                        │
├─────────────────────────────────────────────────────────┤
│                 Sync / Coordinator 层                     │
│  BolaWCSessionCoordinator.shared（单例，跨平台编译）        │
├─────────────────────────────────────────────────────────┤
│              State / Business Logic 层                    │
│  PetViewModel (Watch)     PetCoreState (Shared)          │
│  PetAnimationController   MealEngine                    │
│  CompanionTier            ChatHistoryStore               │
├─────────────────────────────────────────────────────────┤
│                Persistence / Defaults 层                  │
│  BolaSharedDefaults.resolved()  → App Group / standard   │
│  CompanionPersistenceKeys      → UserDefaults 键定义      │
│  KeychainHelper / LLMKeychain  → API 密钥安全存储         │
│  WidgetCenter                  → Widget 时间线刷新        │
└─────────────────────────────────────────────────────────┘
```

### 1.2 设备角色

| 角色 | 权威数据源 | 说明 |
|------|-----------|------|
| Watch（手表） | 陪伴值最终权威 | `PetViewModel` 是陪伴值计算的唯一权威；墙钟加分、扣分、点击 +1 均在 Watch 端发生 |
| iPhone（手机） | 配置 / 设置权威 | LLM 密钥、提醒列表、餐食配置、表盘布局、称号、人格选择等由 iPhone 管理，单向推到 Watch |
| 双向对称 | 聊天记录 | `[ChatTurn]` 双向增量合并（按 UUID 去重） |

---

## 2. 数据持久化层

### 2.1 App Group 配置

| 项目 | 值 |
|------|-----|
| App Group Suite | `group.com.GathXRTeam.BolaBola` |
| 定义位置 | `Shared/Defaults/AppGroupConfig.swift` |
| 需求 | 付费开发者账号 + Entitlements 配置 |
| 降级行为 | Personal Team → `groupSuite` 为 nil → 降级到 `UserDefaults.standard`（无法跨设备共享，但 App 不崩溃） |

代码标记：搜索 `RESTORE_APP_GROUP_WHEN_PAID_DEV` 可找到所有需在付费账号后恢复的点位。

### 2.2 BolaSharedDefaults 解析逻辑

```
BolaSharedDefaults.resolved()
  → 尝试 UserDefaults(suiteName: "group.com.GathXRTeam.BolaBola")
  → 如果非 nil → 返回 App Group suite
  → 如果 nil → 返回 UserDefaults.standard（本地调试兜底）
```

**迁移**：`migrateStandardToGroupIfNeeded()` 在首次检测到 App Group 可用时，把 `allCompanionKeys` 中的值从 `standard` 复制到 App Group，写 `migratedToAppGroupMarker = true`，只执行一次。

### 2.3 CompanionPersistenceKeys — 所有持久化键

| 键名（常量） | UserDefaults Key | 类型 | 默认值 | 说明 |
|---|---|---|---|---|
| `companionValue` | `bola_companionValue` | Double | 50 | 陪伴值（内部精度，0–100） |
| `lastCompanionWallClock` | `bola_lastCompanionWallClock` | Double (timestamp) | 启动时 `now` | 上次墙钟结算时刻 |
| `lastTickTimestamp` | `bola_lastTickTimestamp` | Double (timestamp) | — | 旧版时间戳键，已迁移到 `lastCompanionWallClock` |
| `totalActiveSeconds` | `bola_totalActiveSeconds` | Double | 0 | 累计活跃秒数（驱动惊喜里程碑） |
| `activeCarrySeconds` | `bola_activeCarrySeconds` | Double | 0 | 加分结算后的余数（不满 `secondsPerCompanionBonus` 的部分） |
| `lastSurpriseAtHours` | `bola_lastSurpriseAtHours` | Double | 0 | 上次惊喜触发时的里程碑小时数 |
| `companionWCUpdatedAt` | `bola_companion_wc_updated_at` | Double (timestamp) | 0 | WC 写入陪伴值时的 Unix 时间戳，用于跨设备 Last-Writer-Wins |
| `migratedToAppGroupMarker` | `bola_migrated_to_app_group` | Bool | false | App Group 迁移完成标记 |
| `companionDisplayName` | `bola_companion_display_name_v1` | String | "" | 用户给宠物起的显示名（空则 UI 显示「Bola」） |

**快照键集合**（Watch → iPhone 全量快照时使用）：
- `wcGameStateSnapshotKeys` = `allCompanionKeys` + [`companionWCUpdatedAt`]

### 2.4 ChatHistory 持久化

| 项目 | 值 |
|------|-----|
| 键 | `bola_chat_turns_v1` |
| 格式 | JSON 编码的 `[ChatTurn]` |
| 上限 | `maxTurns = 24`（超出截断尾部） |
| 位置 | `BolaSharedDefaults.resolved()` |

### 2.5 Keychain 存储（LLM 配置）

| Keychain Account | 用途 |
|-----------------|------|
| `LLMKeychain.accountAPIKey` | LLM API Key |
| `LLMKeychain.accountBaseURL` | API Base URL |
| `LLMKeychain.accountModelId` | 模型 ID |
| `LLMKeychain.accountAuthBearer` | Bearer 认证标记 |

> 注意：Keychain 不经 App Group 共享；LLM 配置由 iPhone 通过 WCSession 推送到 Watch。

---

## 3. Companion Value（陪伴值）体系

### 3.1 核心变量定义

**Watch 端（PetViewModel 内部）**：

| 变量 | 类型 | 默认值 | 可见性 | 说明 |
|------|------|--------|--------|------|
| `companionValueInternal` | Double | 50 | private | 内部精度（支持 0.1 级别的扣分），所有计算基于此值 |
| `companionValue` | Double | 50 | @Published | 对外暴露值，始终 = `companionValueInternal.rounded()`，驱动 UI |
| `totalActiveSeconds` | TimeInterval | 0 | private | 累计活跃秒数，驱动惊喜里程碑 |
| `activeCarrySeconds` | TimeInterval | 0 | private | 不满一个加分周期的余数 |
| `lastCompanionWallClockTime` | TimeInterval | 0 | private | 上次墙钟结算的 Unix 时间戳 |
| `lastSurpriseMilestoneHours` | Double | 0 | private | 上次惊喜触发在多少小时里程碑 |

**iOS 端（IOSRootView）**：

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `companion` | Double | 50 | @State，从 `BolaSharedDefaults` 读取，由 WC 回调更新 |

### 3.2 计算参数

| 参数 | 变量名 | 值 | 说明 |
|------|--------|-----|------|
| 加分周期 | `secondsPerCompanionBonus` | **600s**（10 分钟 +1） | 测试值；正式可改回 **3600s**（每小时 +1） |
| 长期离线阈值 | `longAbsenceWithoutForegroundSeconds` | **86400s**（24 小时） | 超过此时间未回到 App 视为长期离线 |
| 扣分宽限期 | `deductionGraceSeconds` | **7200s**（2 小时） | 有效 Gap 的前 2 小时不扣分 |
| 扣分粒度 | `deductionChunkSeconds` | **300s**（5 分钟） | 每个扣分单元 |
| 每单元扣分 | `deductionPerChunk` | **0.1** | 每 5 分钟扣 0.1 分 |
| 夜间豁免 | 硬编码 | 00:00–07:00 | 扣分 Gap 中剔除此时段 |
| 陪伴值范围 | `clampCompanionValue` | **0–100** | 任何计算后都会裁剪到此范围 |
| 惊喜里程碑间隔 | `surpriseMilestoneHours` | **100 小时** | 100→200→300… |

### 3.3 加分机制（墙钟加分）

**触发时机**：
1. **冷启动 hydrate**：`hydrateTotalTimeAndSurpriseState()`
2. **回到前台**：`handleScenePhaseChange(.active)` → `applyWallClockCompanionDeltaFromLastCredit()`
3. **Timer 每 60 秒**：`startMilestoneTimer()` → `accumulateTimeAndMaybeTrigger()`

**计算流程**：

```
delta = now - lastCompanionWallClockTime

if delta > longAbsenceWithoutForegroundSeconds (24h):
    → 走扣分分支（见 3.4）
else:
    → applyActiveAddition(delta)
        activeCarrySeconds += delta
        while activeCarrySeconds >= secondsPerCompanionBonus:
            activeCarrySeconds -= secondsPerCompanionBonus
            companionValueInternal += 1
        companionValueInternal = round(companionValueInternal * 10) / 10
        companionValueInternal = clamp(0...100)
        companionValue = companionValueInternal.rounded()
    → totalActiveSeconds += delta
    → 更新 lastCompanionWallClockTime = now
    → persistCompanionSnapshot()
```

**关键特性**：
- **无每日加分上限**（总分仍受 0–100 约束）
- **24 小时均可加分**（含深夜）
- 进后台/垂腕/睡眠期间：**不推进** `lastCompanionWallClockTime`；在回到前台时按整段墙钟间隔补算

### 3.4 扣分机制（长期离线自动扣分）

**触发条件**：`delta > longAbsenceWithoutForegroundSeconds`（即离线超过 24 小时）

**计算流程**：

```
from = Date(timeIntervalSince1970: lastCompanionWallClockTime)
effectiveGap = deductibleSecondsOutsideNightWindow(from: from, to: now)
    → 遍历 from~to 的每一天
    → 剔除 00:00–07:00 时段
    → 返回剩余有效秒数

applyHydrationGapDeduction(effectiveGap):
    if effectiveGap <= deductionGraceSeconds (2h): 不扣
    excess = effectiveGap - deductionGraceSeconds
    deduction = floor(excess / 300) * 0.1
    companionValueInternal -= deduction
    companionValueInternal = round(companionValueInternal * 10) / 10
    companionValueInternal = clamp(0...100)
    companionValue = companionValueInternal.rounded()

→ 显示 longAbsenceReturn 台词
→ lastCompanionWallClockTime = now（重置起点，不再重复扣）
```

**关键特性**：
- **不把这整段超长间隔按挂机加分**（先扣分分支，不加）
- 扣分无单次上限（离线越久扣越多，最低 0 分）
- 扣分后显示「长期离线回来」台词

### 3.5 点击 +1 机制

**触发**：`cycleEmotionOnTap()` 中普通跳跃路径

**流程**：
```
applyCompanionBonusFromTapJump():
    companionValueInternal += 1
    companionValueInternal = clamp(0...100)
    companionValue = companionValueInternal.rounded()
    persistCompanionSnapshot()  // 写 defaults + WC 推到手机
    tapBonusToken = UUID()      // 驱动界面「+1」泡泡动效

    if 跨档:
        pendingTierSpeechAfterTap = tierChangedLine  // 延后 0.65s 播放
```

**iOS 端的等价路径**：
```
incrementCompanionValueLocally(by: 1):
    v = defaults.companionValue + 1
    v = clamp(0...100)
    pushCompanionValue(v)  // 写 defaults + WC 推到手表
```

### 3.6 陪伴值→情绪映射（Companion Tier & Emotion）

**CompanionTier 分档**（`Shared/Companion/CompanionTier.swift`）：

| 档位 (tier) | v 范围 | 语义 |
|-------------|--------|------|
| 0 | 0–2 | 极低 |
| 1 | 3–9 | 低落 |
| 2 | 10–19 | 委屈 |
| 3 | 20–29 | 不高兴 |
| 4 | 30–39 | 轻过渡 |
| 5 | 40–85 | 主待机大段 |
| 6 | 86–100 | 开心档 |

**默认情绪映射**（`selectDefaultEmotion()`，v = `Int(companionValue.rounded())`）：

| v 范围 | 默认情绪 | 选择规则 |
|--------|---------|---------|
| 0–2 | `.die` | 固定 |
| 3–9 | `.sad1` / `.sad2` | `v % 2 == 0` → `sad2`，否则 `sad1` |
| 10–29 | `.hurt` / `.unhappy` / `.unhappyTwo` | `(v - 10) % 3`：0=hurt, 1=unhappy, 2=unhappyTwo |
| 30–39 | 随机 idle 变体 | `randomIdleEmotion()` |
| 40–85 | idle 变体 + 泡泡 | `v % 5`：0/1/2=idle随机, 3=blowbubble1, 4=blowbubble2 |
| 86–100 | 高档动画 | `happyIdle`（1/6 概率）或 `defaultEmotionForHighTier86To100(v)` |

**86–100 高档映射细节**：
- `v % 5 == 0` → `.like1`（但 v=90 和 v=95 例外，随机选 like2/blowbubble/jump）
- `v % 5 == 1` → `.like2`
- `v % 5 == 2` → 随机 `.jump1` / `.jumpTwo`
- `v % 5 == 3` → `.blowbubble1`
- `v % 5 == 4` → `.blowbubble2`

**展示层随机插入**（`applyDefaultEmotionDisplay()`，v > 2 才参与）：

| 条件 | 概率 | 插入动画 | 播完回退 |
|------|------|---------|---------|
| 深夜 23:30–03:00 | 0.2 | `.sleepy`（一轮） | <30 → 分段默认态；≥30 → 随机 idle |
| v 25–80 | 0.2 | `.shakeOnce`（一轮） | 同上 |
| v > 85 | 0.2 | `.happy1Once`（一轮） | 同上 |

### 3.7 惊喜里程碑机制

**变量**：

| 变量 | 说明 |
|------|------|
| `totalActiveSeconds` | 累计活跃秒数 |
| `lastSurpriseMilestoneHours` | 上次触发的里程碑（0 = 未触发过） |
| `surprisePending` | 当前动画非默认态时排队等待触发 |
| `surpriseJumpTwoQueued` | 惊喜动画播完后是否需再跳一下 |

**触发逻辑**（`maybeTriggerSurpriseIfNeeded()`）：
```
totalHours = totalActiveSeconds / 3600.0
nextMilestone = (lastSurpriseMilestoneHours <= 0)
    ? 100
    : lastSurpriseMilestoneHours + 100

if totalHours >= nextMilestone && lastSurpriseMilestoneHours < nextMilestone:
    if currentEmotion == currentDefaultEmotion:
        → 立即触发
    else:
        surprisePending = true  // 等当前动画播完

触发时：
    lastSurpriseMilestoneHours = nextMilestone
    → 写入 defaults
    → 显示惊喜台词
    → currentEmotion = random(surprisedOne, surprisedTwo)
    → surpriseJumpTwoQueued = true
    → 解锁特殊动画图鉴
```

### 3.8 陪伴值 100 特殊处理

| 事件 | 条件 | 行为 |
|------|------|------|
| 首次达到 100 | `vBeforeTap == 99 && vNow == 100` | 显示 `companionValue100Lines` 台词（duration=8s） |
| 维持在 100 | `v == 100 && currentEmotion == currentDefaultEmotion` | 每 8 分钟（`companion100AmbientCooldownSeconds`）可能再播一句开心话 |

---

## 4. Core State Management（核心状态管理）

### 4.1 PetCoreState 枚举

**定义**（`Shared/Sync/PetCoreState.swift`）：

```swift
public enum PetCoreState: String, Codable, Sendable {
    case idle        // 默认待机
    case hungry      // 饥饿等待喂食
    case thirsty     // 口渴等待喝水
    case sleepWait   // 等待入睡
    case sleeping    // 已入睡
}
```

**核心设计原则**：
- 网线只搬运**结果状态**（idle/hungry/thirsty/sleepWait/sleeping），不搬运过渡动画
- 过渡动画（eating/drinking/fallingAsleep）由本机 `PetAnimationController` 驱动
- 对端只在**结果状态变化**时直接对齐，不重放过渡动画

### 4.2 PetCoreState → iPhone 动画映射

**iPhone 端**使用 `animationPrefix(companionValue:)` 根据 coreState + companionValue 选择动画前缀：

| CoreState | 动画前缀 | 说明 |
|-----------|---------|------|
| `.idle` | 由 `idlePrefix(for:)` 决定 | 与 Watch 的 `selectDefaultEmotion()` 对标 |
| `.hungry` | `"idleapple"` | 固定等待吃苹果 |
| `.thirsty` | `"idledrink1"` / `"idledrink2"` | 随机选一个 |
| `.sleepWait` | `"sleepy"` | 打哈欠 |
| `.sleeping` | `"sleeploop"` | 睡眠循环 |

**iPhone idle 前缀映射**（`idlePrefix(for:)`）：

| v 范围 | 前缀 |
|--------|------|
| 0–2 | `"die"` |
| 3–9 | `v%2==0` → `"sadtwo"`, 否则 `"sadone"` |
| 10–29 | `(v-10)%3`: 0→`"hurt"`, 1→`"unhappy"`, 2→`"unhappytwo"` |
| 30–85 | `"idleone"` |
| 86–100 | `"happyidle"` |

> 注意：iPhone 端是简化版映射，Watch 端更丰富（含泡泡、跳跃等变体）。

### 4.3 PetAnimationController（基础交互状态机）

**定义**：`Shared/Animation/PetAnimationController.swift`

**覆盖范围**：
- 点击跳跃（tapJumpOne / tapJumpTwo）
- 吃东西流程（eatingWait → eatingOnce → eatingHappyIdle / eatingLikeOne / eatingLikeTwo）
- 喝水流程（idleDrinkOne/Two → drinkOnce → blowbubbleOne/Two）
- 夜间睡眠流程（nightSleepWait → fallAsleep → sleepLoop）

**过渡事件枚举**（`PetInteractionTransitionReason`）：

| 事件 | 说明 |
|------|------|
| `tapJumpStarted` | 跳跃开始 |
| `tapJumpCompleted` | 跳跃结束 |
| `hungryStarted` | 进入饥饿等待 |
| `eatingStarted` | 开始吃东西 |
| `eatingFinisherStarted` | 吃完收尾动画 |
| `eatingCompleted` | 吃东西流程结束 |
| `thirstyStarted` | 进入口渴等待 |
| `drinkingStarted` | 开始喝水 |
| `drinkingFinisherStarted` | 喝完收尾动画 |
| `drinkingCompleted` | 喝水流程结束 |
| `sleepWaitStarted` | 进入睡前等待 |
| `fallingAsleepStarted` | 开始入睡动画 |
| `sleepingStarted` | 进入睡眠循环 |
| `cleared` | 强制清除交互状态 |

**设计约束**：
- 副作用（台词、`pushPetCoreState`、本地记账）由平台层通过 `onTransition` 回调处理
- 仅在核心状态**实际变化**时推送（如 hungry→idle），过渡中不推送中间态

### 4.4 PetViewModel（Watch 端核心状态机）

**定义**：`BolaBola Watch App/Views/ContentView.swift`

**关键状态变量**：

| 变量 | 类型 | 说明 |
|------|------|------|
| `currentEmotion` | PetEmotion @Published | 当前播放的情绪动画 |
| `currentFrameIndex` | Int @Published | 当前帧索引 |
| `companionValue` | Double @Published | 对外陪伴值（四舍五入整数） |
| `companionValueInternal` | Double private | 内部精度陪伴值（小数） |
| `currentDefaultEmotion` | PetEmotion private | 当前陪伴值对应的默认情绪 |
| `dialogueLine` | String @Published | 当前气泡文案 |
| `tapBonusToken` | UUID? @Published | 点击 +1 泡泡驱动 |
| `voiceConversationActive` | Bool @Published | 是否在语音对话中 |
| `isInEatingState` | Bool | 吃东西状态机标记 |
| `isInDrinkWaterState` | Bool | 喝水状态机标记 |
| `isInNightSleepState` | Bool | 夜间睡眠状态机标记 |
| `isNightSleepAsleep` | Bool | 是否已进入 sleepLoop |
| `isTapInteractionAnimating` | Bool | 点击动画锁（防连跳） |
| `tapBurstCount` | Int | 8 秒窗口内连击次数 |
| `lastTapBurstAt` | TimeInterval | 上次点击时间 |
| `angryTapCooldownUntil` | TimeInterval | 生气冷却截止时间 |
| `isForegroundActive` | Bool | 是否在前台 |
| `healthKitReadAuthorized` | Bool | HealthKit 读取是否已授权 |

**点击交互规则**（`cycleEmotionOnTap()`）：

| 条件 | 动画 | 台词 | 陪伴值 | 其他 |
|------|------|------|--------|------|
| v ≤ 2（die 段） | 无 | 无 | 不变 | 无交互 |
| 生气冷却中（10s 内） | 无 | 无 | 不变 | |
| 插入动画播放中 | 无 | 无 | 不变 | |
| 8s 窗口内第 9+ 次 | `angry2Once` | `tapAngrySample()` | 不变 | 计数清零，10s 冷却 |
| 8s 窗口内第 3 次 | `like2Once` | `tapTripleLikeSample()` | 不变 | 计数不清零 |
| 其余点击 | `jump1Tap`/`jumpTwoTap` | `tapJumpOpening` + 延后 `tapJumpReturnLine` | **+1** | `tapBonusToken` 驱动 +1 泡泡 |

**播完回退规则**（`resolvedEmotionAfterInteractionOrInsert()`）：
- `v < 30` → 回到当前分段默认态（die/sad/unhappy/hurt）
- `v ≥ 30` → 随机 idle 变体

### 4.5 远程核心状态变更（iPhone → Watch）

当 iPhone 通过 WCSession 推送 `PetCoreState` 变化时，Watch 端 `applyRemoteCoreState()` 的行为：

| 远程状态 | Watch 行为 | 条件 |
|----------|-----------|------|
| `.idle` | 清除 eating/drinkWater 状态，回到默认情绪 | 仅当 `isInEatingState || isInDrinkWaterState` |
| `.hungry` | 进入吃东西等待态 | 仅当不在 eating 态 |
| `.thirsty` | 进入喝水等待态 | 仅当不在 drinkWater 态 |
| `.sleepWait` | 进入夜间睡眠等待态 | 仅当不在 nightSleep 态 |
| `.sleeping` | 进入 sleepLoop | 仅当 `isInNightSleepState && !isNightSleepAsleep` |

**防反馈循环**：`onRemoteCoreStateChange` 只由对端推送触发，本机 `pushPetCoreState` 不会自反馈。

---

## 5. Sync 系统（iPhone↔Watch 同步）

### 5.1 BolaWCSessionCoordinator 单例

**定义**：`Shared/Sync/BolaWCSessionCoordinator.swift`（1218 行）
**模式**：单例 `BolaWCSessionCoordinator.shared`
**编译**：`#if os(iOS) || os(watchOS)` 条件编译，两端共用同一文件

**关键属性**：

| 属性 | 类型 | 平台 | 说明 |
|------|------|------|------|
| `onReceiveCompanionValue` | `((Double) -> Void)?` | 双方 | 收到远端陪伴值时回调 |
| `onRemoteCoreStateChange` | `((PetCoreState) -> Void)?` | 双方 | 收到远端核心状态变化时回调（仅远端触发，防自反馈） |
| `currentPetCoreState` | PetCoreState @Published | 双方 | 当前跨设备同步的核心状态 |
| `currentPetEmotionLabel` | String @Published | iOS only | Watch 推来的当前情绪标签（调试用） |
| `pendingPayload` | `[String: Any]?` | 双方 | Session 未就绪时暂存的陪伴值 payload |
| `pendingChatDeltaPayloads` | `[[String: Any]]` | 双方 | Session 未就绪时暂存的聊天增量队列（上限 32） |
| `debugActivationState` | Int @Published | 双方 | WCSession 激活状态镜像 |
| `debugIsReachable` | Bool @Published | 双方 | 可达性镜像 |
| `debugIsCounterpartInstalled` | Bool @Published | 双方 | 对端 App 安装状态镜像 |

### 5.2 WCSession 通信通道

BolaWCSessionCoordinator 使用三种 WCSession 通道：

#### 通道 1：`updateApplicationContext`

| 项目 | 说明 |
|------|------|
| 语义 | 「最新状态快照」，last-writer-wins |
| 可靠性 | 不保证送达顺序；对端只在**下次激活时**读取 `receivedApplicationContext` |
| 用途 | 陪伴值 + 核心状态的主推送通道 |
| 失败回退 | 抛异常时仍走 `transferUserInfo` 兜底 |

#### 通道 2：`transferUserInfo`

| 项目 | 说明 |
|------|------|
| 语义 | FIFO 队列，保证顺序送达 |
| 可靠性 | 系统排队，对端可达时按序投递 |
| 用途 | 聊天增量、LLM 配置、提醒列表、餐食配置、指令、快照等 |
| 限制 | 队列有上限；超出时 Watch 端 `pendingChatDeltaPayloads` 丢弃最旧的（上限 32） |

#### 通道 3：`sendMessage`

| 项目 | 说明 |
|------|------|
| 语义 | 即时消息，需对端可达 |
| 可靠性 | 不可达时失败 |
| 用途 | 宠物指令（eat/drink/sleep）的快速路径 |
| 失败回退 | `sendMessage` 失败 → 自动回退到 `transferUserInfo` |

### 5.3 WCSyncPayload — 所有 WC 键定义

**定义**：`Shared/Sync/WCSyncPayload.swift`

#### 陪伴值 / 核心状态

| 键 | 类型 | 方向 | 说明 |
|----|------|------|------|
| `companionValue` | Double | 双向 | 陪伴值 |
| `companionValueUpdatedAt` | TimeInterval | 双向 | 陪伴值写入时的 Unix 时间戳 |
| `companionSyncForcedFromPhone` | Bool | iPhone→Watch | 强制同步标记（跳过时间戳比较） |
| `petCoreState` | String (rawValue) | 双向 | 宠物核心状态 |
| `petEmotionLabel` | String | Watch→iPhone | 当前情绪动画标签（调试用） |

#### LLM 配置

| 键 | 类型 | 方向 | 说明 |
|----|------|------|------|
| `llmApiKey` | String | iPhone→Watch | API Key |
| `llmBaseURL` | String | iPhone→Watch | API Base URL |
| `llmModelId` | String | iPhone→Watch | 模型 ID |
| `llmAuthBearer` | String ("1"/"0") | iPhone→Watch | 是否使用 Bearer 认证 |
| `requestSync` | String | Watch→iPhone | 请求同步标记 |
| `requestSyncValueLLMKeychain` | "llmKeychain" | — | 请求 LLM Keychain 同步 |

#### 聊天增量

| 键 | 类型 | 方向 | 说明 |
|----|------|------|------|
| `chatDeltaKind` | "v1" | 双向 | 聊天增量版本标记 |
| `chatDeltaDataB64` | String (Base64) | 双向 | `[ChatTurn]` JSON 的 Base64 |

#### 陪伴游戏状态快照

| 键 | 类型 | 方向 | 说明 |
|----|------|------|------|
| `companionSnapshotKind` | "csV1" | Watch→iPhone | 快照版本标记 |
| `companionSnapshotB64` | String (Base64) | Watch→iPhone | UserDefaults 可序列化子集的二进制 plist Base64 |

#### Watch 表盘 / 成长 / 称号

| 键 | 类型 | 方向 | 说明 |
|----|------|------|------|
| `watchFaceSlotsB64` | String (Base64) | iPhone→Watch | `WatchFaceSlotsConfiguration` JSON |
| `titleSelectionB64` | String (Base64) | iPhone→Watch | `BolaTitleSelection` JSON |
| `personalitySelectionRaw` | String | iPhone→Watch | 人格选择（"default" / "tsundere"） |
| `growthStateB64` | String (Base64) | iPhone→Watch | `BolaGrowthState` JSON |
| `titleUnlockedIdsB64` | String (Base64) | iPhone→Watch | 已解锁称号 ID 数组 JSON |
| `specialAnimationUnlockedIdsB64` | String (Base64) | 双向 | 已解锁动画 ID 数组 JSON |
| `maxEverCompanionValue` | Double | iPhone→Watch | 历史最高陪伴值 |

#### 提醒 / 餐食

| 键 | 类型 | 方向 | 说明 |
|----|------|------|------|
| `remindersListB64` | String (Base64) | iPhone→Watch | `[BolaReminder]` JSON |
| `mealSlotsB64` | String (Base64) | iPhone→Watch | `[MealSlot]` JSON |

#### 宠物指令

| 键 | 类型 | 方向 | 说明 |
|----|------|------|------|
| `petCommandKind` | String | iPhone→Watch | 指令类型（"eat"/"drink"/"sleep"） |
| `petCommandId` | String (UUID) | iPhone→Watch | 指令 ID（Watch 端去重用） |

#### 语音中继

| 键 | 类型 | 方向 | 说明 |
|----|------|------|------|
| `speechRelayRequestId` | String | Watch→iPhone | 语音请求 ID |
| `speechRelayKind` | String | 双向 | 中继类型标记 |
| `speechRelayTranscript` | String | iPhone→Watch | 转写文本 |
| `speechRelayError` | String | iPhone→Watch | 转写错误 |

### 5.4 数据流详解

#### 5.4.1 iPhone → Watch

| 数据 | 推送方法 | 触发时机 | 通道 |
|------|---------|---------|------|
| 陪伴值 + 核心状态 | `pushCompanionValue()` | iOS 点击宠物 +/-；`activationDidComplete`；`sessionWatchStateDidChange`；`sessionReachabilityDidChange` | applicationContext + transferUserInfo |
| LLM 配置 | `pushLLMConfigurationToWatch()` | 用户保存 LLM 设置 | transferUserInfo |
| LLM 配置（自动） | `pushStoredLLMConfigurationToWatchIfConfigured()` | `activationDidComplete`；Watch 请求时 | transferUserInfo |
| 提醒列表 | `pushReminderRefreshToWatchIfPossible()` | 用户修改提醒；`activationDidComplete` | transferUserInfo |
| 餐食配置 | `pushMealSlotsToWatchIfPossible()` | 用户修改餐食；`activationDidComplete` | transferUserInfo |
| Watch 表盘 + 成长 + 称号 | `appendWatchHomeScreenPayload()` | 随 `pushCompanionValue()` 一起发出 | applicationContext + transferUserInfo |
| 宠物指令 | `sendPetCommand()` | 用户在 iPhone Mockup 触摸宠物 | sendMessage（快速路径）→ transferUserInfo（回退） |
| 聊天增量 | `pushChatDelta()` | 对话回合结束 | transferUserInfo |

#### 5.4.2 Watch → iPhone

| 数据 | 推送方法 | 触发时机 | 通道 |
|------|---------|---------|------|
| 陪伴值 + 核心状态 | `pushCompanionValue()` | 墙钟结算；点击 +1；`sessionCompanionStateDidChange` | applicationContext + transferUserInfo |
| 情绪标签（调试） | `sendPetEmotionLabelNow()` | 情绪动画变化 + 调试面板开启 | transferUserInfo |
| 陪伴游戏状态快照 | `pushCompanionGameStateSnapshotToPhoneNow()` | 墙钟结算后防抖（1.5s） | transferUserInfo |
| LLM Keychain 请求 | `requestLLMKeychainFromPhoneIfMissing()` | Watch 本地无 API Key；`activationDidComplete`（45s 节流） | transferUserInfo |
| 聊天增量 | `pushChatDelta()` | 对话回合结束 | transferUserInfo |
| 语音文件中继 | `transferFile()` | 用户按住说话 | file transfer |

### 5.5 冲突解决（Reconciliation）

#### 5.5.1 陪伴值 Last-Writer-Wins

**核心逻辑**（`ingest()` 方法）：

```
收到远程 payload:
  v = payload.companionValue
  tsRaw = payload.companionValueUpdatedAt
  forcedFromPhone = payload.companionSyncForcedFromPhone
  localTs = defaults.companionWCUpdatedAt

  // 确定远程时间戳
  if tsRaw > 0:
      remoteTs = tsRaw
  else if localTs == 0 || forcedFromPhone:
      remoteTs = Date.now  // 无法判断时间时，用当前时间
  else:
      return  // 本地有更新时间戳且非强制 → 丢弃

  // 时间戳守卫
  if !forcedFromPhone:
      guard remoteTs > localTs else return  // 远程不比本地新 → 丢弃

  // 应用
  defaults.companionValue = v
  storedTs = forcedFromPhone ? Date.now : remoteTs  // 强制时用当前时间，防后续往返被旧戳覆盖
  defaults.companionWCUpdatedAt = storedTs
  onReceiveCompanionValue?(v)
```

**强制同步场景**：iPhone 调用 `pushLocalCompanionTowardWatchFromDefaults()` 时设置 `forcedForWatch = true`，确保 Watch 端即使本地时间戳更新也接受该值。

#### 5.5.2 PetCoreState 即时同步

- `petCoreState` **不受时间戳守卫限制**，始终在收到后立即应用
- `onRemoteCoreStateChange` 回调仅由对端推送触发
- 设计原因：核心状态变化代表用户交互结果（如点击喂食），不应被旧时间戳阻塞

#### 5.5.3 陪伴游戏状态快照合并

Watch → iPhone 的全量快照（`ingestCompanionGameStateSnapshotFromWatchIfPresent`）：

```
// 非陪伴值字段：始终采用 Watch 端的值
for key in allCompanionKeys where key != companionValue:
    defaults[key] = remote[key]

// 陪伴值：如果 Watch 端 WC 时间戳 >= 本地，才采用
if remote.companionWCUpdatedAt >= local.companionWCUpdatedAt - 0.0001:
    defaults.companionValue = remote.companionValue
```

#### 5.5.4 聊天记录合并

```
mergeRemoteTurns(remote):
    local = load()
    seen = Set(local.map(\.id))
    for turn in remote where !seen.contains(turn.id):
        local.append(turn)
    local.sort(by: createdAt)
    save(local.suffix(maxTurns))
```

### 5.6 队列与缓冲机制

| 队列 | 类型 | 上限 | 溢出策略 | 清空条件 |
|------|------|------|---------|---------|
| `pendingPayload` | 单条 | 1 | 后者覆盖前者 | Session 激活后发送或丢弃 |
| `pendingChatDeltaPayloads` | FIFO 队列 | 32 | 丢弃最旧的 | Session 就绪后 FIFO 发出 |
| `recentPetCommandIds` | 去重列表 | 16 | 移除最早的 | — |

### 5.7 节流与去重

| 机制 | 参数 | 说明 |
|------|------|------|
| LLM Keychain 请求节流 | 45 秒 | `llmKeychainPullThrottleSeconds`，避免 Watch 反复请求 |
| 情绪标签防抖 | 300ms | `petEmotionLabelDebounceTask`，合并快速连续的情绪变化 |
| 宠物指令去重 | 最近 16 个 ID | `recentPetCommandIds`，避免重复处理同一指令 |
| 陪伴快照防抖 | 1.5s | `companionGameStateSnapshotDebounceTask`，避免每 tick 刷屏 |

### 5.8 Session 生命周期

#### 激活流程

```
BolaBolaApp.init() / IOSAppDelegate
  → BolaWCSessionCoordinator.shared.activate()
  → WCSession.default.delegate = self
  → WCSession.default.activate()

activationDidCompleteWith:
  → refreshDebugSessionState()
  → ingest(receivedApplicationContext)        // 先消费对端最新状态
  → 处理 pendingPayload                      // 发送暂存数据
  → [iOS] pushStoredLLMConfigurationToWatchIfConfigured()
  → [iOS] pushLocalCompanionTowardWatchFromDefaults()
  → [iOS] pushReminderRefreshToWatchIfPossible()
  → [iOS] pushMealSlotsToWatchIfPossible()
  → [iOS] postWatchInstallabilityChanged()
  → flushPendingChatDeltasIfReady()
  → [Watch] requestLLMKeychainFromPhoneIfMissing()
```

#### 状态变化回调

| 回调 | 平台 | 行为 |
|------|------|------|
| `sessionWatchStateDidChange` | iOS | 配对/安装状态变化 → 刷新调试 + 推 LLM + 推陪伴值 + 推提醒/餐食 |
| `sessionReachabilityDidChange` | iOS | 可达性变化 → 刷新调试 + flush chat + 推配置 |
| `sessionCompanionStateDidChange` | watchOS | iPhone 安装状态变化 → flush chat + 推陪伴值 + 推快照 + 请求 LLM |

#### 消息接收分发

```
didReceiveApplicationContext:
  → ingest(applicationContext)

didReceiveUserInfo:
  → 先应用 petCoreState（不受时间戳守卫限制）
  → [iOS] 检查 requestSync == "llmKeychain" → pushStoredLLM
  → [Watch] 检查 speechRelayReply → 处理语音转写结果
  → [Watch] 检查 petCommand → 发通知给 PetViewModel
  → 检查 chatDelta → mergeRemoteTurns
  → [iOS] 检查 companionSnapshot → 合并快照
  → [iOS] 检查 petEmotionLabel → 镜像到调试面板
  → 检查 LLM 配置 → 写入 Keychain
  → 都不匹配 → ingest() → 陪伴值 Last-Writer-Wins

didReceiveMessage:
  → 与 didReceiveUserInfo 类似分发逻辑
```

---

## 6. NotificationCenter 事件表

| 事件名 | 发送方 | 接收方 | 说明 |
|--------|--------|--------|------|
| `.bolaChatHistoryDidChange` | ChatHistoryStore.save | UI | 本地聊天记录写入 |
| `.bolaChatHistoryDidMerge` | ingestChatDeltaIfPresent | UI | WC 远端聊天合并完成 |
| `.bolaWatchInstallabilityDidChange` | postWatchInstallabilityChanged | iOS UI | Watch 安装状态变化 |
| `.bolaCompanionStateDidMergeFromWatch` | ingestCompanionSnapshot | iOS UI | Watch 快照合并完成 |
| `.bolaOpenSettingsRequested` | — | iOS | 打开设置 |
| `.bolaLLMConfigurationDidChange` | — | UI | LLM 配置变化 |
| `.bolaPetCommandReceived` | ingestPetCommandIfPresent | PetViewModel | 收到 iPhone 指令 |
| `.bolaMealSlotsDidUpdate` | ingestMealSlotsIfPresent | Watch UI | 餐食配置更新 |
| `.bolaWatchHomeScreenPayloadDidUpdate` | ingestWatchHomeScreenPayload | Watch UI | 表盘/称号/成长数据更新 |

---

## 7. 关键流程时序

### 7.1 Watch 冷启动

```
App 启动
  → BolaWCSessionCoordinator.shared.activate()
  → PetViewModel.init()
      → migrateStandardToGroupIfNeeded()
      → 绑定 onReceiveCompanionValue / onRemoteCoreStateChange
      → hydrateTotalTimeAndSurpriseState()
          → 从 defaults 读取 companionValue (默认 50)
          → 从 defaults 读取 totalActiveSeconds, activeCarrySeconds
          → migrateLastCompanionWallClockFromDefaults()
          → creditOrPenalizeWallClockGapIfNeeded()
              → if delta > 24h: 扣分 + 长期离线台词
              → else: 加分 + 累计活跃时间
          → persistCompanionSnapshot(pushToPhone: false)  // 冷启动不推送
          → lastSurpriseMilestoneHours = defaults.lastSurpriseAtHours
      → selectDefaultEmotion()
      → applyDefaultEmotionDisplay()
      → startMilestoneTimer()  // 每 60s tick
      → startProactiveChatTimer()
      → maybeTriggerSurpriseIfNeeded()
  → WCSession activationDidComplete
      → ingest(receivedApplicationContext)
      → [Watch] requestLLMKeychainFromPhoneIfMissing()
```

### 7.2 iPhone 点击宠物（同步到 Watch）

```
iPhone 用户点击宠物
  → incrementCompanionValueLocally(by: 1)
      → v = defaults.companionValue + 1
      → v = clamp(0...100)
      → pushCompanionValue(v)
          → 写 defaults (companionValue, companionWCUpdatedAt)
          → 构建 payload (companionValue, companionValueUpdatedAt, petCoreState, watchHomeScreen...)
          → sendPayload()
              → updateApplicationContext(payload)  // 失败也继续
              → transferUserInfo(payload)

Watch 收到 applicationContext / userInfo
  → ingest()
      → petCoreState 立即应用
      → 陪伴值 Last-Writer-Wins 时间戳比较
      → onReceiveCompanionValue?(v)
          → applyRemoteCompanionValue(v)
              → companionValueInternal = clamp(v)
              → companionValue = rounded()
              → persistCompanionSnapshot(pushToPhone: false)
              → selectDefaultEmotion() + applyDefaultEmotionDisplay()
              → trackCompanionTierSpeechIfNeeded()
```

### 7.3 Watch 点击宠物（同步到 iPhone）

```
Watch 用户点击宠物
  → cycleEmotionOnTap()
      → applyCompanionBonusFromTapJump()
          → companionValueInternal += 1
          → companionValue = rounded()
          → persistCompanionSnapshot(pushToPhone: true)
              → BolaWCSessionCoordinator.shared.pushCompanionValue(companionValueInternal)
              → schedulePushCompanionGameStateSnapshotToPhoneDebounced()
          → tapBonusToken = UUID()  // +1 泡泡

iPhone 收到 payload
  → ingest()
      → 陪伴值 Last-Writer-Wins
      → onReceiveCompanionValue?(v)
          → companion = v
```

### 7.4 LLM 配置同步

```
Watch 本地无 API Key
  → requestLLMKeychainFromPhoneIfMissing()
      → transferUserInfo([requestSync: "llmKeychain"])
      → 45s 节流

iPhone 收到 requestSync
  → pushStoredLLMConfigurationToWatchIfConfigured()
      → 从 Keychain 读取 apiKey, baseURL, modelId, authBearer
      → pushLLMConfigurationToWatch()
          → transferUserInfo([llmApiKey, llmBaseURL, llmModelId, llmAuthBearer])

Watch 收到 LLM 配置
  → ingestLLMConfigurationIfPresent()
      → 写入 Watch 本地 Keychain
```

### 7.5 聊天记录同步

```
任一端产生新对话
  → ChatHistoryStore.appendUserThenAssistant()
  → BolaWCSessionCoordinator.shared.pushChatDelta(turns)
      → 编码 [ChatTurn] → JSON → Base64
      → payload = {chatDeltaKind: "v1", chatDeltaDataB64: b64}
      → if session ready: transferUserInfo(payload)
      → else: enqueueChatDeltaPayload(payload)  // 上限 32

对端收到
  → ingestChatDeltaIfPresent()
      → 解码 Base64 → JSON → [ChatTurn]
      → ChatHistoryStore.mergeRemoteTurns(turns)  // 按 ID 去重，按时间排序
      → post bolaChatHistoryDidMerge
```

---

## 8. 附录：变量速查表

### 8.1 PetViewModel 核心变量（Watch）

| 变量 | 类型 | 默认 | 作用 |
|------|------|------|------|
| `companionValueInternal` | Double | 50 | 内部精度陪伴值 |
| `companionValue` | Double @Published | 50 | 对外暴露（四舍五入） |
| `totalActiveSeconds` | TimeInterval | 0 | 累计活跃秒数 |
| `activeCarrySeconds` | TimeInterval | 0 | 加分余数 |
| `lastCompanionWallClockTime` | TimeInterval | 0 | 上次墙钟结算时刻 |
| `lastSurpriseMilestoneHours` | Double | 0 | 上次惊喜里程碑 |
| `currentEmotion` | PetEmotion @Published | .idle | 当前动画 |
| `currentDefaultEmotion` | PetEmotion | .idle | 当前默认情绪 |
| `dialogueLine` | String @Published | "" | 当前气泡文案 |
| `tapBonusToken` | UUID? @Published | nil | +1 泡泡驱动 |
| `isInEatingState` | Bool | false | 吃东西标记 |
| `isInDrinkWaterState` | Bool | false | 喝水标记 |
| `isInNightSleepState` | Bool | false | 夜间睡眠标记 |
| `isNightSleepAsleep` | Bool | false | 已入睡标记 |
| `isTapInteractionAnimating` | Bool | false | 点击动画锁 |
| `tapBurstCount` | Int | 0 | 连击计数 |
| `angryTapCooldownUntil` | TimeInterval | 0 | 生气冷却截止 |
| `voiceConversationActive` | Bool @Published | false | 语音对话中 |
| `isForegroundActive` | Bool | true | 前台标记 |
| `healthKitReadAuthorized` | Bool | false | HealthKit 授权 |

### 8.2 BolaWCSessionCoordinator 关键属性

| 属性 | 类型 | 作用 |
|------|------|------|
| `currentPetCoreState` | PetCoreState @Published | 跨设备核心状态 |
| `currentPetEmotionLabel` | String @Published | Watch 情绪标签（iOS 调试） |
| `onReceiveCompanionValue` | `((Double) -> Void)?` | 收到远端陪伴值回调 |
| `onRemoteCoreStateChange` | `((PetCoreState) -> Void)?` | 收到远端核心状态回调 |
| `pendingPayload` | `[String: Any]?` | 暂存陪伴值 payload |
| `pendingChatDeltaPayloads` | `[[String: Any]]` | 暂存聊天增量队列 |

### 8.3 PetCoreState 与动画前缀映射

| CoreState | Watch 动画 | iPhone 动画前缀 | 台词 |
|-----------|-----------|----------------|------|
| `.idle` | 由 companionValue 决定 | `idlePrefix(for:)` | nil |
| `.hungry` | `eatingWait` (idleapple) | `"idleapple"` | "有点饿，想吃东西啦" |
| `.thirsty` | `idleDrink1`/`idleDrink2` | `"idledrink1"` / `"idledrink2"` | "有点渴啦" |
| `.sleepWait` | `nightSleepWait` (sleepy) | `"sleepy"` | "已经很晚了，好想睡觉" |
| `.sleeping` | `sleepLoop` | `"sleeploop"` | nil |

---

> **文档维护说明**：本文档基于代码主分支自动生成，如代码有重大变更请同步更新。键名定义以 `CompanionPersistenceKeys.swift`、`WCSyncPayload.swift` 为准；计算规则以 `companion_value_rules.md`、`state_machine_list.md` 为准。
