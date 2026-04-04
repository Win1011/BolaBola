# BolaBola iPhone 产品需求（三板块 + 双数值）

**版本**：2026-04  
**范围**：以 iPhone 伴侣 App 为主的信息架构与功能说明；手表仍为互动与陪伴值的主场景，详见下文引用。

---

## 1. 产品定位与平台分工

- **iPhone**：设置与密钥、数据汇总与健康可视化、生活与日记、游戏化进度（等级值、任务、图鉴）、表盘与称号的配置与预览。
- **Apple Watch**：宠物主界面、陪伴值驱动的状态机与动画、语音与轻量互动；技术细节与计分规则以手表端文档为准。
- **关系**：iPhone 的「Watch」向板块展示模拟表盘与同步能力；成长板块解锁的组件 / 图鉴项可配置到表盘预留位（产品目标，分阶段实现）。

---

## 2. 信息架构：四格底栏与三板块映射

根导航采用 **四个底栏项**，**从左到右顺序**为：**主界面**、**成长**、**生活**、**对话**（`IOSRootView` 中 `TabSection` 内顺序与此一致）。前三个对应 **三大产品板块**；对话独立为 LLM 入口。

设计稿中常见「生活 / 成长 / 我的」与工程枚举、文案需对齐，避免沟通歧义。推荐映射如下。

| 底栏（目标文案） | 产品板块 | 主要模块 |
|------------------|----------|----------|
| 主界面 | **Watch 与称号** | 模拟表盘、自定义表盘组件位、称号系统、陪伴值展示与同步 |
| 成长 | **游戏化** | 等级值、每日任务、解锁图鉴（特殊动画等）；未来 Bola 相关游戏化扩展优先放此 Tab |
| 生活 | **数据与记录** | HealthKit 可视化、提醒、今日生活记录；子页「时光」为日记时间线 |
| 对话 | （独立） | 与 Bola 的 LLM 对话（配置见 Keychain / 设置） |

**与当前工程的大致对应**（随迭代以代码为准）：

- 生活：`BolaBola iOS/Features/Life/IOSLifeContainerView.swift`、子导航 `IOSLifeSegmentLarge`（生活｜时光）。
- 成长：目标为替换原「状态」Tab 的内容；当前 `Features/Status/IOSStatusView.swift` 为 Health 习惯分析，**产品上将迁入「生活」**，成长 Tab 承载等级 / 任务 / 图鉴（待实现）。
- 主界面：`Features/Home/IOSMainHomeView.swift`（模拟表盘、同步、表盘布局占位、陪伴值）。
- 根 Tab：`BolaBola iOS/App/IOSRootView.swift`、`Features/Home/IOSRootTab.swift`。

---

## 3. 板块一：Watch 页（主界面 Tab）

**自上而下信息结构（与 Figma 对齐）**

1. **模拟 Apple Watch**  
   - 展示时间与宠物画面预览；与真实手表数据通过 WatchConnectivity 同步（陪伴值、后续表盘组件等）。  
   - **预览几何**：表镜「光学中心」、表镜矩形与组件内边距以工程内单一数据源为准（`WatchS10PreviewGeometry`）；后续在表盘图或表镜上方叠加的自定义图标、装饰图等均相对该锚点布局。说明见 [`watch_s10_preview_geometry.md`](watch_s10_preview_geometry.md)。

2. **同步与快捷操作**  
   - 例如「同步手表」：推送陪伴值、LLM 配置等（行为以 `BolaWCSessionCoordinator` 为准）。

3. **陪伴值（与板块关系）**  
   - 在此展示当前陪伴值及与手表一致的状态；**语义见第 6 节**，计分与状态机**不**在本 PRD 重复定义，以 [`BolaBola Watch App/Documentation/companion_value_rules.md`](../BolaBola%20Watch%20App/Documentation/companion_value_rules.md) 与 [`state_machine_list.md`](../BolaBola%20Watch%20App/Documentation/state_machine_list.md) 为准。

4. **自定义表盘组件**  
   - 工程内已有表盘 **布局/占位**（如 `HomeWatchFaceLayout`、主界面内布局选择器）。  
   - **产品目标**：用户可将成长页解锁的「组件」长按拖拽到表盘预留区域，自定义位置。  
   - **分期**：v1 可为「仅选择预设布局」；拖拽上表为后续迭代，需在交互稿与开发任务中单列。

5. **称号系统**  
   - 展示当前称号、进度或收集状态。  
   - **解锁条件**：建议与 **等级值里程碑或任务成就** 挂钩，与陪伴值解耦（避免与「生死档」情绪规则纠缠）；具体称号表待策划补全。

---

## 4. 板块二：成长 Tab（替换原「状态」）

**自上而下信息结构**

1. **等级值**  
   - 展示 `LV.x` 与升至下一级的进度条；旁可附说明入口（「i」）。  
   - **用途**：解锁特殊奖励（见下），长期养成进度，与「陪伴值」区分（见第 6 节）。

2. **Bola 主视觉与引导文案**  
   - 例如「快来看看今日三个随机任务」类提示，强化每日回访与任务入口。

3. **每日任务**  
   - 任务类型可包含：与 HealthKit 相关的散步/运动、与对话/提醒/陪伴行为相关的任务等（具体列表与数值策划待定）。  
   - **完成判定**需在技术任务书中拆到可观测事件（HealthKit 查询、对话次数、提醒完成等）。

4. **解锁内容 / 图鉴**  
   - 展示已解锁与未解锁的特殊动画或装扮类条目（类似图鉴）。  
   - **与 Watch 联动**：复制产品文案意图——「长按图标拖拽到表盘即可自定义位置」；实现依赖表盘组件模型与同步策略。

**原「状态」Tab 中的 HealthKit 习惯与图表**：产品上 **并入「生活」Tab**（见第 5 节），不再单独占一栏。

**数据与同步**：等级、任务进度、解锁状态若需跨 iPhone / Watch 或备份，依赖 App Group、`UserDefaults` 与 WatchConnectivity；无可靠共享容器时的限制见 [`app_group_removal_and_restore.md`](./app_group_removal_and_restore.md)。PRD 层可标 **v1 仅本机持久化**，跨端同步另立迭代。

---

## 5. 板块三：生活 Tab（数据类）

**导航结构**

- 顶栏 **「生活 | 时光」** 分段（实现见 `IOSLifeToolbarCenter.swift` / `IOSLifeSegmentLarge`）。
- **生活**：节奏/今日概览、**提醒**（如「Bola 正在关心的事」）、**今日生活记录**（天气、事件等卡片）。
- **时光**：日记式时间线；从占位示例到真实持久化可作为独立里程碑写在路线图。

**从「状态」并入**

- HealthKit 相关习惯分析与图表（当前 `IOSStatusView` / `IOSHealthHabitAnalysisSection`）在产品上归入 **生活 Tab 的某一 Section**，与节奏、提醒、记录并列或置于合适滚动顺序。

**能力边界**

- 健康数据为 **陪伴与习惯参考**，非医疗诊断；表述需与 [`health_reminders_platform.md`](../BolaBola%20Watch%20App/Documentation/health_reminders_platform.md) 等平台声明一致。

---

## 6. 双数值：陪伴值与等级值

### 6.1 定义（产品语义）

| 概念 | 产品语义 | 工程锚点 |
|------|----------|----------|
| **陪伴值** | 短期关系强度与「是否活着、开不开心」等 **即时体验**；驱动手表上的情绪、动画与对话语境 | `companionValue` 0–100，Watch 与 iPhone 同步逻辑见 Shared 与 WC 文档 |
| **等级值** | **长期进度**；用于 **解锁奖励**（图鉴条目、表盘组件、称号等），偏成就与养成 | 尚未统一实现，需新模型与 UI |

陪伴值 **权威规则**（加分、长期离线惩罚、与状态机映射）以手表文档为准，**iPhone PRD 不另起一套数值**。

### 6.2 两者关系（可选方案，供决策）

未在 v1 强制选定一种；落地时应在策划文档中定稿并配表。

- **方案 A — 正交**  
  陪伴只影响情绪与即时反馈；等级经验只来自任务、成就、登录 streak 等。**用户理解成本最低。**

- **方案 B — 软挂钩**  
  例如陪伴过低时 **减缓** 等级经验获取，或部分称号要求「曾达到某陪伴阈值」；**不改变** 陪伴值主规则。

- **方案 C — 单向奖励**  
  等级提升或任务完成给予 **小额** 陪伴值加成（**严格每日上限**），用于庆祝感或补救感，避免替代手表端核心陪伴逻辑。

**设计原则**：避免同一行为被设计成「重复刷两种货币」；若采用方案 C，必须写明上限与目的（庆祝 / 补救），并防止挤压纯陪伴玩法的空间。

---

## 7. 非功能与依赖

- **WatchConnectivity**：陪伴值等上下文同步；聊天与 LLM 配置走 `transferUserInfo` 等路径（见 `CLAUDE.md` 与项目状态文档）。
- **App Group**：个人开发者证书等场景下可能回退到非共享 `UserDefaults`，影响双端共享键；详见 [`app_group_removal_and_restore.md`](./app_group_removal_and_restore.md)。
- **Firebase Analytics**：仅 iOS 目标；手表不链 Analytics。

---

## 8. 相关文档索引

| 文档 | 说明 |
|------|------|
| [`PRD_v1.md`](../BolaBola%20Watch%20App/Documentation/PRD_v1.md) | **手表端** v1 范围说明（已加「iPhone 见本文档」的交叉引用） |
| [`companion_value_rules.md`](../BolaBola%20Watch%20App/Documentation/companion_value_rules.md) | 陪伴值计分规则 |
| [`state_machine_list.md`](../BolaBola%20Watch%20App/Documentation/state_machine_list.md) | 陪伴值与状态机 / 动画 |
| [`项目状态与后续工作_2026-03.md`](./项目状态与后续工作_2026-03.md) | 工程状态与已知债 |
| 仓库根目录 `CLAUDE.md` | 架构与模块速查 |

---

## 9. 路线图提示（非承诺）

- 成长 Tab：等级模型、任务系统、图鉴与解锁管线。  
- 生活 Tab：合并 Health 分析区、时光日记持久化。  
- 主界面：称号数据、表盘组件拖拽与 WC 下发。  
- 数值：定稿陪伴值与等级值关系（第 6.2 节）。

本文档随产品迭代更新；若与实现不一致，**以仓库内代码与手表专项文档为执行准绳**，并回写本文档。
