## BolaBola Watch AI 宠物 v1.0 PRD（精简版）

**文档范围**：本文档仅描述 **watchOS** 端 v1 范围。  
**iPhone 伴侣 App** 的产品信息架构（三板块、四格底栏、等级值与陪伴值等）见仓库内 [`Documentation/PRD_iPhone_三板块_2026-04.md`](../../Documentation/PRD_iPhone_三板块_2026-04.md)。

---

### 1. 产品定位
- **目标**：在 Apple Watch 上提供一个「陪伴型 AI 宠物」，通过轻量互动和健康提醒增加陪伴感。
- **平台**：仅 watchOS 独立 App，后续再扩展 iPhone 端。

### 2. v1 必做功能
- **宠物主界面**
  - 显示当前时间 + 宠物 2D 动画（idle / blink / breathing / wag tail / nod / thinking）。
  - 通过简单状态机切换基础动作（例如空闲时 idle+breathing，偶尔 blink）。
- **对话入口**
  - 点击主界面某个按钮进入对话页。
  - v1 可以先用固定回复（本地 mock），之后再接入真正的 LLM。
- **提醒入口**
  - 用户在 Watch 上选择「添加提醒」（先用简单表单或语音占位）。
  - 通过与 iPhone/云端的通信（后续实现）真正创建系统提醒或待办。
- **健康提醒（占位）**
  - 先预留数据模型（如步数、站立时间、睡眠质量等字段），文案可先写死。
  - 后续接入 HealthKit/iPhone 端逻辑后再真实驱动。
- **陪伴值**
  - 定义一个 0–100 的陪伴值，通过「看宠物」「发起对话」「完成提醒」等行为增加。
  - v1 只在本地存储（UserDefaults），展示一个简单进度条或等级文本。

### 3. 动画策略
- **基础动作（A 类）**：使用 SVG 拆层 + SwiftUI 动画（位移 / 缩放 / 透明度）实现 idle / blink / breathing / wag tail / nod / thinking。
- **高表现动作（B 类）**：使用 AI 生成的视频转出的 PNG 序列帧，在 Watch 上按帧播放：
  - 开心庆祝、睡觉、撒娇、生气、节日特殊动作等。
  - 单段动画建议控制在 8–15 帧内，以节省体积和内存。

### 4. 技术架构（v1）
- **UI 框架**：SwiftUI。
- **架构模式**：MVVM。
  - `PetViewModel`：管理宠物当前情绪、动作状态、当前动画帧。
  - `PetStateMachine`：定义宠物情绪 / 动作状态（idle / happy / angry / sleep 等）的切换规则。
  - `PetAnimation`：描述每个动作对应的 PNG 序列（资源名前缀、总帧数、帧率）。
- **数据存储**：UserDefaults 存陪伴值、简单偏好；后续扩展到 iPhone/云端同步。

### 5. v1 范围外（以后版本再做）
- 真正的 LLM 云端对话与记忆系统。
- 实际 HealthKit 接入与复杂健康规则。
- 商城与内购、装扮系统。
- 完整 iPhone 端大屏管理应用。

