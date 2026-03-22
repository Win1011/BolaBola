# 点击交互规则（Tap）

实现：`PetViewModel.cycleEmotionOnTap()`（`ContentView.swift`）。点击用 **`jump1Tap` / `jumpTwoTap`** 随机播一轮（两套跳跃资源）；另有 `like2Once` / `angry2Once` 同理为单轮播放。

---

## 1. 条件 → 动画 → 台词

| 条件 | 动画 | 台词（池） | 备注 |
|------|------|------------|------|
| 陪伴值 `v ≤ 2`（die 段） | 无 | 无 | **无交互** |
| 处于 **生气冷却**（上次生气后 10 秒内） | 无 | 无 | `angryTapCooldownUntil` |
| **正在播放**点击插入动画 | 无 | 无 | `isTapInteractionAnimating`，避免连跳 |
| **8 秒窗口**内第 **9 次及以后**点击（`tapBurstCount > 8`） | `angry2Once`（播一轮） | `tapAngrySample()` | 计数清零；**10 秒冷却**；播完回 **当前分段默认态**（见下） |
| 窗口内第 **3** 次点击（`tapBurstCount == 3`） | `like2Once`（播一轮） | `tapTripleLikeSample()` | **不**清零计数，便于继续点到第 9 次生怒；播完回 **当前分段默认态** |
| **其余点击** | `jump1Tap` / `jumpTwoTap`（随机） | `tapJumpOpening` → 播完 `tapJumpReturnLine` | 每次有效跳跃 **+1 陪伴值**；`tapBonusToken` 驱动 **+1 泡泡**动效；跨档台词延后 |

**窗口**：距上次点击 **> 8 秒**则 `tapBurstCount` 归零后再计本次为第 1 次。

---

## 2. 播完回到的基态（非「永远 idle」）

- 由 `resolvedEmotionAfterInteractionOrInsert()` 决定：
  - **陪伴值 `< 30`**：回到**当前分段默认态**（见 `selectDefaultEmotion()`：die / sad / unhappy / hurt 等），**不**强行随机 idle 变体。
  - **`≥ 30`**：**idleOne / idleTwo / idleThree** 中 **随机** 其一（`randomIdleEmotion()`）。
- 仅 **普通跳跃**（`shouldPlayTapJumpFollowUp == true`）在播完后额外播 **`tapJumpReturnLine`**；跨档台词若由 `+1` 触发，则**延后**再播 `tierChangedLine`，避免顶掉跳跃开场白。

---

## 3. 与惊喜、非循环动画

- **惊喜**仍用 `surprisedOne` / `surprisedTwo` / `jumpTwoOnce` 等逻辑，**不**走 `tapChainReturnsToRandomIdle`。
- 点击触发的跳跃/喜欢/生气播完后通过 `tapChainReturnsToRandomIdle` 回基态；其它非循环结束仍走 `selectDefaultEmotion()` 与陪伴值默认池。
