# 宠物状态机清单（陪伴值驱动草案 v3）

## 0) 陪伴值定义（时间挂钩）
陪伴值 `companionValue` 取值范围：`0...100`（会做上下限裁剪）。**完整计分规则见 `companion_value_rules.md`。**

摘要（与实现一致，细节见 `companion_value_rules.md`）：
- **加分**（墙钟间隔，Timer / 回前台 / hydrate 结算）：每累计 **1 小时** → **+1**，carry 保留；**无每日加分上限**（总分仍 **0…100**）；**24 小时均可加分**（含深夜）。
- **扣分**（墙钟间隔 **>24 小时** 未回到 App 时自动触发）：Gap 先 **剔除 00:00~07:00**，有效 Gap **≤2 小时不扣**；超出部分每 **5 分钟 -0.1**，**随离线变长而增加**（无单次 −8 封顶，最低 0 分）。
- 状态机分段判定时，陪伴值取**四舍五入后的整数**。

陪伴值到**默认动画**的映射（与 `ContentView.swift` 中 `selectDefaultEmotion()` 一致；`companionValue` 取四舍五入整数 `v`）：
- `0...2`：`die`
- `3...9`：`sad1` / `sad2`（`v % 2` 二选一，稳定）
- `10...29`：`unhappy` 与 `hurt` 按分数稳定映射（约 35% 为 `hurt`，见 `unhappyTierHurtStride`；避免墙钟反复重算时随机抖动）
- `30...39`：`idleOne` / `idleTwo` / `idleThree` 随机
- `40...85`：`idleOne` / `idleTwo` / `idleThree` / `blowbubble1` / `blowbubble2`（`v % 5` 五选一）
- `86...100`：`like1` / `like2` / `jump1` **或** `jumpTwo`（`v % 5` 的「跳跃」档内随机二选一）/ `blowbubble1` / `blowbubble2`（`v % 5` 五选一）

**展示层随机插入**（在 `applyDefaultEmotionDisplay()` 中，于 `selectDefaultEmotion()` 之后；`v>2` 才参与；概率为代码常量，默认各约 0.2）：
- **深夜** 本地时间 **23:30–次日 03:00**：可能插入 `sleep`（`sleepy` 资源，**播一轮**）→ 播完 **陪伴值 `<30`** 回到当前分段默认态（die/sad/unhappy/hurt），**≥30** 回到随机 `idleOne/Two/Three`
- **`25...80`**：可能插入 `shakeOnce`（`shake` 播一轮）→ 同上规则（`<30` 回分段默认，`≥30` 回随机 idle）
- **`v > 85`（86–100）**：可能插入 `happy1Once`（`happyone` 播一轮）→ 同上（仅 `≥30` 会用到此插入）

**边界说明**：`85` 归入 **40–85** 大段；**86–100** 为开心档（若产品要改边界，只改 `selectDefaultEmotion` 一处即可）。

## 1) 状态列表（State）
- `idle`：默认待机循环
- `idleOne`：待机变体循环
- `idleTwo`：待机变体2循环
- `idleThree`：待机变体3循环
- `scale`：缩放动作循环
- `die`：死亡/结局动作循环
- `angry2`：生气动作循环
- `unhappy`：不高兴动作循环
- `letter`：信件动作循环
- `hurt`：委屈动作循环
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
- `surprisedOne`：惊喜1动作循环
- `surprisedTwo`：惊喜2动作循环
- `sad1`：难过1循环
- `sad2`：难过2循环
- `jumpTwo` / `jump1`：跳跃动作循环（高陪伴默认池内随机）
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
- `BaseLoop`：`idle` / `idleOne` / `idleTwo` / `idleThree`
- `InteractionLoop`：`like*` / `question*` / `speak*` / `blowbubble*`
- `MoodLoop`：`die` / `angry2` / `unhappy` / `hurt` / `sad*`
- `NeedLoop`：`sleepy`
- `ChatReaction`：语音交互后的反应（`question*` / `speak*`）

## 4) 陪伴值分段 -> 主状态（核心规则）
以 `companionValue`（0~100）为主输入，**默认态**按以下区间映射（与实现一致）：

- `0...2`：`die`（持续循环）
- `3...9`：`sad1` / `sad2`
- `10...29`：`unhappy` / `hurt`（按分数稳定映射，约 1/3 档为 `hurt`）
- `30...39`：`idleOne` / `idleTwo` / `idleThree` 随机
- `40...85`：`idleOne` / `idleTwo` / `idleThree` / `blowbubble1` / `blowbubble2`
- `86...100`：`like1` / `like2` / `jump1` 或 `jumpTwo` / `blowbubble1` / `blowbubble2`

`question*` / `speak*` / `letter` 等可作为**插入态**由其它规则触发，不作为本表默认池。

补充规则：
- `sleep`（`sleepy` 资源、非循环一轮）与 `shakeOnce`、`happy1Once` 为**展示插入**，见上文「展示层随机插入」
- `sleepy` 循环态仍保留枚举，可用于其它规则
- `die` 覆盖态会随着 `companionValue` 升高自动结束，并回到当前陪伴值对应分段主状态（即默认状态）

默认状态的含义（用于“播完回去”）：
- 默认状态 = 根据当前 `companionValue` 落入的分段，选择得到的“主状态/主池中选中的一个”
- 默认状态会持续循环；所有“插入/奖励动作”（如惊喜、互动、letter）播完后都回到默认状态

## 5) 转移规则（建议）
- 初始进入：根据当前陪伴值直接落到对应分段主状态
- 陪伴值变化：重新评估分段并切换
- 点击宠物：只在当前分段允许的动作池中切换（不跨分段）
- 无事件：保持当前循环状态
- 动作超时后：回到当前分段主状态（不是固定回 `idle`）
- 用户说话后：优先进入 `ChatReaction`，完成后再回到当前分段主状态

惊喜机制（100 小时里程碑，100->200->300...）：
- 记录总活跃时长换算为 `totalHours`
- 记录并保存上一次触发的里程碑 `last_surprise_hours`（首次用 `0` 表示未触发过）
- 计算下一次触发点：`nextSurpriseHours = (last_surprise_hours == 0 ? 100 : last_surprise_hours + 100)`
- 当 `totalHours >= nextSurpriseHours` 且该档未触发过时触发一次 `SurpriseReward`
- `SurpriseReward` 行为链路：
  - 特效提示（建议 1 秒，“宠物周围闪一圈微光”，资源待确认；先用占位也可）
  - 随机选择 `surprisedOne` / `surprisedTwo` 播放 2 轮后进入下一步
  - 额外播放一次 `jump1Once` 或 `jumpTwoOnce`（随机），2 轮长度后回默认展示（含插入随机）
- 幂等保护：触发后保存 `last_surprise_hours = nextSurpriseHours`，下次只在更高档位（例如 200）触发

“播完回默认状态”的通用规则：
- `SurpriseReward` 以及所有由计时器/事件触发的插入动作（如 `scale`、`jumpTwo`、`letter`、`question/speak` 插入）统一满足：播放循环 2 次 -> 回默认状态

## 6) 对话反应链路（新增）
目标：`question*` 系列不再只是随机动作，而是“用户和 Bola 说话后的反应动画”。

建议链路：
- `onUserSpeechStart`：暂停当前普通插入动作，进入 `question1`（固定停留 `2s`，不循环）
- `onUserSpeechResult(success)`：
  - 成功：进入 `question2`（固定停留 `3s`，表示“思考/准备”）
  - 失败：进入 `question3`（固定停留 `3s`，表示“没听清”）
- `onBolaReplyReady`：随机进入 `speak1/speak2/speak3`（播放 2 轮后结束）
- 对话动作结束：恢复普通插入动作的计时，并回到当前 `companionValue` 分段主状态

补充（特殊场景）：
- 若在触发 chat reaction 时刚好到 `sleepy`：先播完 `sleepy` 再补全 chat 链路
- 若 chat 过程中再次点击说话：中断当前 chat 动作，重新从 `question1` 开始

## 7) 插入动作频率（建议）
用于控制“看起来有活力但不过于跳”：
- `0~2`：die（无插入动作）
- `3~9`：sad1/sad2（每 `30~40s` 低概率插入 `hurt`）
- `10~19`：unhappy（每 `25~35s` 中概率插入 `hurt`）
- `20~39`：sad1（每 `20~30s` 低概率插入 `question1`）
- `40~59`：idleOne/idleTwo（每 `15~25s` 插入 `scale`）
- `60~69`：question1/question2（每 `10~18s` 插入 `speak1`）
- `70~79`：speak1/speak2（每 `8~15s` 插入 `question2`）
- `80~89`：like1/idleThree（每 `6~12s` 插入 `jumpTwo`）
- `90~100`：like2/blowbubble2（每 `6~10s` 插入 `jumpTwo`/`blowbubble1`）
- 若正在 `ChatReaction`：暂停普通插入动作，避免抢状态

letter/hurt 的补充建议（让动画更生动）：
- `letter`：当用户刚发生“外部事件”（例如收到 Bola 文本回复、或用户刚查看/确认某信息）时，按概率插入；播完回默认状态
- `hurt`：当 `companionValue` 偏低但未到 `unhappy/sad*` 的强覆盖阈值时（例如 `20...29`），按低概率插入，让角色显得更有情绪变化

## 8) 优先级（建议）
- `sleepy`（最高）
- `chat reaction`（question/speak，对话触发）
- `angry2` / `sad*`
- `interaction`（like/question/speak/blowbubble）
- `idle` / `idleOne` / `idleTwo` / `idleThree`（最低）

## 9) 防抖与稳定性（建议）
- 陪伴值跨段后，至少停留 `5~8s` 再允许下一次跨段（避免边界抖动）
- 边界加滞回（hysteresis）：
  - 例如从 `sad1` 升回 `idle` 需要 `>=45`
  - 从 `idle` 降回 `sad1` 需要 `<=35`
- 每个状态设置最短停留时间 `minStateDuration`（例如 3~5 秒）

## 10) 待确认（你拍板）
- “低概率/中概率/低频插入”的具体数值（例如 `hurt` 插入概率用多少？20% 还是 40%？）
- 5 分钟级别扣减的“四舍五入”落点：状态机分段判定是否直接用 `round()` 后整数（当前实现：内部保留小数，状态判定用四舍五入后的整数）
- `die`->复活后“首次点击触发 hurt”是否需要强制？如何定义“首次点击”（从 die->20 的第一下？还是复活后 10 秒内？）
- 100h 特效提示动画资源是否已有？若没有：是否先复用占位动画（例如把 `surprisedOne` 的前帧当作特效）？
- “惊喜后额外跳一下”是否需要严格 2 轮后回默认（当前实现：我已加了 `jumpTwoOnce` 来满足这一点）
- chat reaction / sleepy / 插入动作的“播放固定时长/固定轮次后回默认”在代码侧目前还没完全落地，你希望用“新增 *Once 非循环动画”这一策略继续吗？

## 11) 下一步实现清单
- 增加 `PetEvent` 枚举
- 增加 `PetStateMachine`（纯逻辑，不依赖 UI）
- 增加 `companionValue` 输入与分段判定函数
- 增加 `ChatReaction` 子状态与说话事件处理
- `PetViewModel` 只负责：接收事件 -> 查询下一个状态 -> 更新当前动画
- 保留 `DEBUG` 开关：测试模式按点击顺序遍历所有动作
