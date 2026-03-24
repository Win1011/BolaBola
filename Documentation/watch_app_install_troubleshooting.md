# Watch 伴侣 App 装不上 / 表盘没有图标 — 排查备忘

## 1. 最低系统版本（常见根因）

若 **Watch App 的 `WATCHOS_DEPLOYMENT_TARGET`** 高于你手表实际系统版本，**系统不会安装**嵌入的 Watch App，Run iOS 后主屏也可能一直看不到表端。

- 本工程 **BolaBola Watch App** 当前为 **watchOS 26.0** 起；**watchOS 26.3** 等设备满足要求。
- 若手表是 **10 / 11** 等旧系统，须在 Xcode 把 **Minimum Deployments** 降到 **≤ 手表版本**（例如 11.0），否则会装不上。

**自查**：iPhone「设置 → 通用 → 关于本机」里看 **Watch** 的系统版本；Xcode 里 **Watch target → General → Minimum Deployments** 必须 **≤** 该版本。

---

## 2. 工程配置（本仓库预期状态）

- **Scheme `BolaBola`**：`Run` 的可执行文件应是 **iOS `BolaBola.app`**，不是单独 Watch Scheme。
- **iOS target** 含 **Embed Watch Content**，且依赖 **BolaBola Watch App** target（`project.pbxproj` 里已有）。
- Run 目的地选 **真机 iPhone**（已配对 Apple Watch），不是仅 **iOS Simulator**（模拟器不会把表端装到你手腕上的表）。

---

## 3. 安装与系统行为

- Run 成功后，表端常需 **几秒到一两分钟** 才出现在手表；也可打开 iPhone **「Watch」App → 我的手表 → 下方 App 列表** 找到 **BolaBola**，打开 **「显示 App」** / 手动安装。
- **自动下载 App**（或类似）关闭时，可能需手动在 Watch App 里打开。

---

## 4. 签名与能力

- **Personal Team**：避免 entitlements 里声明 **profile 未包含** 的能力（例如曾导致问题的 App Group）。**HealthKit** 等若签名报错，看 Xcode **Report** 里具体提示。
- 会员过期 / 描述文件异常时，以 Xcode 报错 + 真机 **Console** 过滤 `installd`、`BolaBola` 为准（见此前对话中的 Console 方案）。

---

## 5. 仍失败时

1. **Product → Clean Build Folder**，再 Run 到 iPhone。  
2. 在 Finder 中检查构建产物：`BolaBola.app` 内应有 **`Watch` 目录** 及 **`BolaBola Watch App.app`**（路径随 Derived Data 变化，可在 Xcode Report 里展开 **Copy** 步骤确认）。  
3. 手表上 **删掉** 旧版 BolaBola（若有），再重新 Run。

---

*若你调高 `WATCHOS_DEPLOYMENT_TARGET` 以使用新 API，需用 `@available` 等为旧系统提供降级路径，否则勿高于用户手表版本。*
