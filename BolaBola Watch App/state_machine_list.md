# 宠物状态机清单（陪伴值驱动草案 v2）

## 1) 状态列表（State）
- `idle`：默认待机循环
- `idleOne`：待机变体循环
- `scale`：缩放动作循环
- `angry2`：生气动作循环
- `question1`：疑问动作1循环
- `question2`：疑问动作2循环
- `question3`：疑问动作3循环
- `speak1`：说话动作1循环
- `speak2`：说话动作2循环
- `speak3`：说话动作3循环
- `blowbubble1`：吹泡泡1循环
- `blowbubble2`：吹泡泡2循环
- `like1`：点赞1循环
- `like2`：点赞2循环
- `sad1`：难过1循环
- `sad2`：难过2循环
- `sleepy`：困了循环

## 2) 触发事件（Event）
- `onTapPet`：用户点击宠物
- `onCompanionValueChanged`：陪伴值变化（核心驱动）
- `onTimerIdleVariant`：待机轮换计时触发（可选）
- `onActionTimeout`：动作持续一段时间后自动切回基础待机
- `onUserSpeechStart`：用户开始说话
- `onUserSpeechResult`：语音识别得到结果（成功/失败）
- `onBolaReplyReady`：Bola 文本回复已生成

## 3) 基础状态分组（建议）
- `BaseLoop`：`idle` / `idleOne`
- `InteractionLoop`：`like*` / `question*` / `speak*` / `blowbubble*`
- `MoodLoop`：`angry2` / `sad*`
- `NeedLoop`：`sleepy`
- `ChatReaction`：语音交互后的反应（`question*` / `speak*`）

## 4) 陪伴值分段 -> 主状态（核心规则）
以 `companionValue`（0~100）为主输入，推荐先按以下区间映射：

- `0...19`：`sad2`（持续循环，不主动退出）
- `20...39`：`sad1`（循环）
- `40...59`：`idle` / `idleOne`（基础待机，按计时交替）
- `60...79`：`question1/2/3`、`speak1/2/3`（低频插入）
- `80...100`：`like1/2`、`blowbubble1/2`（高频插入）

补充规则：
- `sleepy` 作为“需要休息”的覆盖态，可由额外条件触发（例如长时间无交互或时段规则）
- 覆盖态结束后，回到当前陪伴值对应分段主状态

## 5) 转移规则（建议）
- 初始进入：根据当前陪伴值直接落到对应分段主状态
- 陪伴值变化：重新评估分段并切换
- 点击宠物：只在当前分段允许的动作池中切换（不跨分段）
- 无事件：保持当前循环状态
- 动作超时后：回到当前分段主状态（不是固定回 `idle`）
- 用户说话后：优先进入 `ChatReaction`，完成后再回到当前分段主状态

## 6) 对话反应链路（新增）
目标：`question*` 系列不再只是随机动作，而是“用户和 Bola 说话后的反应动画”。

建议链路：
- `onUserSpeechStart`：可短暂进入 `question1`（表示在听）
- `onUserSpeechResult(success)`：
  - 识别成功：`question2` 或 `speak1`（表示理解/准备回应）
  - 识别失败：`question3`（表示没听清）
- `onBolaReplyReady`：进入 `speak2` 或 `speak3`（表示 Bola 正在回应）
- 反应动作结束后：回到陪伴值分段主状态（idle/sad/like 等）

动作选择策略（先简单）：
- 从对应动作池中“随机一个”，并避免与上一次重复
- 对话反应优先级高于普通插入动作（但低于 `sleepy` 强制态）

## 7) 插入动作频率（建议）
用于控制“看起来有活力但不过于跳”：

- `0...39`：几乎不插入互动动作（主打 `sad*`）
- `40...59`：每 `15~25s` 可插入一次 `scale` 或 `question1`
- `60...79`：每 `10~18s` 插入一次 `question*` 或 `speak*`
- `80...100`：每 `6~12s` 插入一次 `like*` 或 `blowbubble*`
- 若正在 `ChatReaction`，暂停普通插入动作，避免抢状态

## 8) 优先级（建议）
- `sleepy`（最高）
- `chat reaction`（question/speak，对话触发）
- `angry2` / `sad*`
- `interaction`（like/question/speak/blowbubble）
- `idle` / `idleOne`（最低）

## 9) 防抖与稳定性（建议）
- 陪伴值跨段后，至少停留 `5~8s` 再允许下一次跨段（避免边界抖动）
- 边界加滞回（hysteresis）：
  - 例如从 `sad1` 升回 `idle` 需要 `>=45`
  - 从 `idle` 降回 `sad1` 需要 `<=35`
- 每个状态设置最短停留时间 `minStateDuration`（例如 3~5 秒）

## 10) 待确认（你拍板）
- 是否保留“点击顺序轮播全部动作”的测试模式
- 正式模式里，`onTapPet` 是“固定顺序”还是“分段内随机”
- `sleepy` 触发后是否允许点击立即打断
- `angry2` 是否纳入陪伴值分段（例如极低值时替代 `sad2`）
- 各分段插入动作频率是否按上面建议值执行
- 对话触发时 `question*` / `speak*` 的具体映射是否按上面链路

## 11) 下一步实现清单
- 增加 `PetEvent` 枚举
- 增加 `PetStateMachine`（纯逻辑，不依赖 UI）
- 增加 `companionValue` 输入与分段判定函数
- 增加 `ChatReaction` 子状态与说话事件处理
- `PetViewModel` 只负责：接收事件 -> 查询下一个状态 -> 更新当前动画
- 保留 `DEBUG` 开关：测试模式按点击顺序遍历所有动作
