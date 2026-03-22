# 动作清单

- `shake`
- `idleone`
- `idleTwo`
- `idleThree`
- `scale`
- `die`
- `angry2`
- `unhappy`
- `letter`
- `hurt`
- `question1`
- `question2`
- `question3`
- `speak1`
- `speak2`
- `speak3`
- `blowbubble1`
- `blowbubble2`
- `like1`
- `like2`
- `surprisedone`
- `surprisetwo`
- `sad1`
- `sad2`
- `jumptwo`
- `happyone`（happy1 文件夹，36 帧）
- `jumpone`（jump1 文件夹，36 帧）
- `sleepy`
- **插入/一次性（非循环一轮）**：`shakeOnce`（同 `shake`）、`sleep`（同 `sleepy` 资源，深夜随机）、`happy1Once`（同 `happyone`）、`jump1Tap` / `jumpTwoTap`（点击跳）、`jump1Once` / `jumpTwoOnce`（惊喜后双轮跳）

**行为摘要**：
- 陪伴 **25–80**：展示默认态时有机会插入 **shake 一轮**，播完回随机 idleone/idletwo/idlethree。
- **本地 23:30–03:00**：有机会插入 **sleep 一轮**（sleepy 帧），播完回随机 idle。
- **陪伴 >85**：有机会插入 **happy1 一轮**，播完回随机 idle。
- **点击**普通跳：**jumpone** 与 **jumptwo** 随机一轮；高陪伴默认池中跳跃档为 **jump1 / jump2** 随机循环。

建议还需要做的动作（用于让宠物交互更完整）：
- `blink`：眨眼（循环）
- `happy`：开心（短动作或循环）
- `excited`：兴奋/跳动（短动作）
- `yawn`：打哈欠（短动作）
- `wakeUp`：醒来（短动作）
- （已实现）`sleep`：深夜随机插入一轮（`sleepy` 资源），播完回 idle
- `pat`：被抚摸/蹭蹭（短动作）
- `clap`：鼓掌（短动作）
- `surprised`：惊讶（短动作）
- `scared`：害怕/惊吓（短动作）
- `cry`：哭/委屈（短动作）
- `bounce`：弹跳/蹦一下（短动作）

测试串联顺序（点击切换用）：
`shake -> idleone -> idleTwo -> idleThree -> scale -> die -> angry2 -> unhappy -> letter -> hurt -> question1 -> question2 -> question3 -> speak1 -> speak2 -> speak3 -> blowbubble1 -> blowbubble2 -> like1 -> like2 -> surprisedone -> surprisetwo -> sad1 -> sad2 -> jumptwo -> happyone -> jumpone -> sleepy`
