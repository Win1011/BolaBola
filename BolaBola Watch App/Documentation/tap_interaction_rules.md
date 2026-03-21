# 点击交互规则（Tap）

实现：`PetViewModel.cycleEmotionOnTap()`（`ContentView.swift`）。点击用 **`jumptwo` 同一套资源** 的「播一轮」模式（代码里叫 `jumpTwoTap`），另有 `like2Once` / `angry2Once` 同理为单轮播放。

---

## 1. 条件 → 动画 → 台词

| 条件 | 动画 | 台词（池） | 备注 |
|------|------|------------|------|
| 陪伴值 `v ≤ 2`（die 段） | 无 | 无 | **无交互** |
| 处于 **生气冷却**（上次生气后 10 秒内） | 无 | 无 | `angryTapCooldownUntil` |
| **正在播放**点击插入动画 | 无 | 无 | `isTapInteractionAnimating`，避免连跳 |
| **8 秒窗口**内第 **9 次及以后**点击（`tapBurstCount > 8`） | `angry2Once`（播一轮） | `tapAngrySample()` | 计数清零；**10 秒冷却**；播完回 **idle 随机三选一** |
| 窗口内第 **3** 次点击（`tapBurstCount == 3`） | `like2Once`（播一轮） | `tapTripleLikeSample()` | **不**清零计数，便于继续点到第 9 次生怒；播完回 **idle 随机三选一** |
| **其余点击** | `jumpTwoTap`（`jumptwo` 只播一轮） | `tapJumpSample()` | 播完回 **idle 随机三选一** |

**窗口**：距上次点击 **> 8 秒**则 `tapBurstCount` 归零后再计本次为第 1 次。

---

## 2. 播完回到的「idle」

- 指 **idleOne / idleTwo / idleThree** 中 **随机** 其一（`randomIdleEmotion()`）。
- **陪伴值默认态**里凡应出现三种待机之一时（如 30–39、40–85 中带 idle 池的分段），也改为 **随机** 三 idle，避免总停在 idleOne。

---

## 3. 与惊喜、非循环动画

- **惊喜**仍用 `surprisedOne` / `surprisedTwo` / `jumpTwoOnce` 等逻辑，**不**走 `tapChainReturnsToRandomIdle`。
- 点击触发的跳跃/喜欢/生气播完后通过 `tapChainReturnsToRandomIdle` 回随机 idle；其它非循环结束仍走 `selectDefaultEmotion()` 与陪伴值默认池。
