# Bola 台词规则（界面文字气泡）

实现：文案池 `BolaDialogueLines`（`BolaDialogueLines.swift`）+ `PetViewModel.showDialogue(_:duration:)` 用 **`ZStack` 叠在宠物上方** 显示圆角气泡（**不占布局高度**），避免台词出现时主区域变矮导致 `scaledToFit` 重算、跳跃像被「突然放大」；陪伴值用 `safeAreaInset(edge: .bottom)`；**不播放语音**。

- 每次显示新气泡时，`WKInterfaceDevice.current().play(.click)` **轻触反馈**（与「说话」同步）。
- **新一句会替换**当前气泡内容并重新计时消失。
- 默认展示约 **5 秒**后淡出（心率提醒等可略长）。

---

## 1. 触发类型总表

| 触发类 | 时机 | 频率 / 节流 | 内容方向 |
|--------|------|----------------|----------|
| **冷启动 / 回到前台** | `onViewAppear` + `scenePhase == .active` 均调用 `speakForegroundGreetingIfNeeded()` | **约 12 秒内不重复**（防同一次打开触发两次）；之后每次再进入前台都会问候 | 问候；低陪伴：安慰向；高陪伴：撒娇向 |
| **陪伴值分段变化** | `companionValue` 四舍五入后，分段档 `tier` 变化时 `trackCompanionTierSpeechIfNeeded()` | 仅在跨档时 1 句 | 与 `companionTier` 0–6 档一致 |
| **主动闲聊** | `Timer` 约 **每 25 分钟** | **仅前台** `isForegroundActive` | 轮换池 `idleChatter` |
| **长期离线后回来** | `creditOrPenalizeWallClockGapIfNeeded` 走「长期离线」分支 | 每次该分支 1 句 | `longAbsenceReturn` |
| **惊喜里程碑** | `maybeTriggerSurpriseIfNeeded` 真正触发惊喜动画时 | 每次里程碑 1 句 | `surpriseMilestone` |
| **点击反馈** | `cycleEmotionOnTap` | 每次有效点击 1 句（生气 / 跳跃 / 三连 like 不同池） | 见 `tap_interaction_rules.md` |
| **心率偏快（非医疗）** | `onViewAppear` → `HealthKitManager.elevatedHeartRateDialogueLineIfNeeded` | 进入视图时查最近样本；超阈值才显示 | `heartRateFast(bpm)` |
| **系统通知文案** | 本地通知 `ReminderScheduler`（与 App 内气泡独立） | 喝水约 **2h**、站立约 **3h** 重复 | `drinkWaterReminder` / `standUpNudge` |

---

## 2. 分段档 `companionTier`（与台词一致）

陪伴值取整 `v`：

| 档 | v 范围 | 说明 |
|----|--------|------|
| 0 | 0–2 | 极低 |
| 1 | 3–9 | 低落 |
| 2 | 10–19 | 委屈段 |
| 3 | 20–29 | 不高兴 |
| 4 | 30–39 | 轻过渡 |
| 5 | 40–85 | 主待机大段 |
| 6 | 86–100 | 开心档 |

跨档示例句见代码 `tierChangedLine(from:to:)`。

---

## 3. 台词池（与代码同步）

以下为 **开场 / 分段** 等池子；具体字符串以 `BolaDialogueLines` 为准。

### 3.1 回到前台问候 `greetingsLow` / `greetingsMid` / `greetingsHigh`

- **Low**（tier 0–2）：安慰、等待感。
- **Mid**（tier 3–4）：日常陪伴。
- **High**（tier 5–6）：积极、撒娇。

### 3.2 主动闲聊 `idleChatter`

短句轮换，例如：关心一天、提醒休息眼睛、伸懒腰、**喝水**（与通知互补，非医学判定）。

### 3.3 惊喜 `surpriseMilestone`

里程碑达成感谢、庆祝向。

### 3.4 长期离线 `longAbsenceReturn`

委屈 / 「等你」向，与扣分数值无强绑定。

### 3.5 Health / 通知 `heartRateFast` / `drinkWaterReminder` / `standUpNudge`

- 心率：App 内气泡为温馨提醒，**非诊断**。
- 喝水 / 站立：**系统通知**里的文案；习惯提醒，**非传感器判定身体缺水**。

---

## 4. 平台与免责声明

- 手表屏幕较小，气泡使用 **caption2**、最多约 **5 行**，过长文案可在池中拆短句。
- Health 相关台词仅为**陪伴型提示**；心率、步数等不构成医疗建议。详见 `health_reminders_platform.md`。
