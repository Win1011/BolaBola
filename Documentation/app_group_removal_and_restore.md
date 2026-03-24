# App Group 移除后的影响与恢复说明

本文记录：**为何暂时去掉 App Group**、**对功能的影响**、**代码里已做的补偿**，以及 **续费后如何恢复**。便于日后查阅；工程内可搜索标记 **`RESTORE_APP_GROUP_WHEN_PAID_DEV`** 定位相关注释与 entitlements 模板。

---

## 1. App Group 在本项目中的作用（有 group 时）

有 App Group 时，`BolaSharedDefaults.resolved()` 会优先使用：

`UserDefaults(suiteName: "group.com.gathxr.BolaBola")`

**iPhone 主 App 与 Watch App 读写同一块「共享偏好」**（同一容器内的 UserDefaults）。

---

## 2. 从 entitlements 去掉 App Group 之后（当前行为）

当 entitlements 中不再包含 `com.apple.security.application-groups`（且开发者账号侧未配置对应能力）时，`UserDefaults(suiteName:)` 无法使用有效的共享 suite，实现会 **fallback 到各进程自己的 `UserDefaults.standard`**：

- **iPhone 上的 BolaBola**：一份本地 standard  
- **Watch 上的 BolaBola**：另一份本地 standard  

二者在磁盘上 **不共享**。

**动机简述**：Personal Team 等场景下 entitlements 声明了 App Group 但 provisioning profile 未包含时，可能导致 **伴侣 App 安装失败**；去掉声明可避免该类不一致。

---

## 3. 几乎不受影响或已通过其他方式对齐的部分

### 3.1 陪伴数值（主界面 +/-）与 WC 时间戳

- 仍通过 **WatchConnectivity**（`updateApplicationContext` / `transferUserInfo` 及既有 `ingest` 逻辑）。
- **不依赖** App Group 即可把当前陪伴值传到另一端。

### 3.2 陪伴「游戏状态」（累计活跃、墙钟、惊喜档等）

- **以前**：高度依赖共享 UserDefaults；手表写入后，手机若要看同一套数据需依赖 group。
- **现在**：实现 **手表 → iPhone** 的防抖快照（payload kind `csV1`，见 `BolaWCSessionCoordinator`），将 `CompanionPersistenceKeys.wcGameStateSnapshotKeys` 同步到 **iPhone 的 standard**。
- **手机刚点的 +/-**：通过 **`companionWCUpdatedAt`** 比较，避免被较旧的快照覆盖。

### 3.3 试聊 / 聊天记录（`ChatHistoryStore`）

- 跨端一致主要依赖 **`pushChatDelta` + `mergeRemoteTurns`**，而非「两端始终读同一磁盘上的 plist」。
- **有 WC 同步路径时**，体验可接近以前共用 suite 的情况。
- **若一端长期离线、从未收到 delta**，两端本地持久化仍可不一致（见第 4 节）。

### 3.4 LLM 配置（Keychain）

- 本来就不走 App Group，而是 **Keychain + 手机向手表推送**。与移除 App Group **无关**。

---

## 4. 仍会受影响、两端容易不一致的部分

以下数据均通过 `BolaSharedDefaults.resolved()` 读写；无 App Group 时为 **各端独立 standard**，**当前无**与陪伴快照同级别的「全量双向同步」（除非后续单独实现 WC / 云端）。

### 4.1 提醒列表（`ReminderListStore`）

- iPhone：`IOSRootView` / `IOSAnalysisView` 等。  
- Watch：`WatchDrawerAndChrome` 等。  
- **结果**：两端列表 **不会自动一致**。

### 4.2 每日总结 / Digest（`DailyDigestConfig`、`DailyDigestStorageKeys`）

- 配置、上次生成正文、日期等存在 **各端自己的 defaults**。  
- **结果**：例如仅在手表生成的总结存在手表；手机侧通知/点按逻辑读手机 defaults，**可能对不齐**。

### 4.3 通知桥接（`BolaNotificationBridgeKeys.digestTapOpen`）

- 表示「用户点了通知要打开总结」等标记。  
- **结果**：**仅在写入端** 生效，另一端默认不知道。

### 4.4 聊天记录的「未同步」场景

- 若很少通过 WC 传 delta（例如只在一端使用），两端 `ChatHistoryStore` 的持久化 **各自独立**。  
- **结果**：不像「共用一个 suite 时一写两端可见」；依赖 **已发生的 WC 合并** 才能对齐。

### 4.5 `migrateStandardToGroupIfNeeded()`

- 有 App Group 时：可将旧版留在 **standard** 的陪伴相关键 **迁入 group**。  
- 无 App Group 时：`groupSuite == nil`，迁移 **直接返回**，不执行拷贝。

### 4.6 日志中的 `appGroup` 标记

- 如 `ChatHistoryStore` 日志里的 `appGroup` 会为 **false**，仅用于诊断，**不改变业务逻辑**。

### 4.7 与系统能力的关系

- 移除 App Group **不会**自动移除 HealthKit、推送、WC 等其它 entitlement。  
- 影响范围主要是：**曾假设「手机与手表读同一 UserDefaults 容器」的功能**。

### 4.8 未来扩展（Widget、App Extension 等）

- 若需与主 App **共享本地 prefs/文件**，常见做法仍依赖 App Group 或改为服务端；无 group 时需另设计数据路径。

---

## 5. 汇总表

| 领域 | 有 App Group 时 | 关掉后（当前实现） |
|------|-----------------|-------------------|
| 陪伴数值（+/-） | 共享 + WC | **WC，行为接近** |
| 陪伴游戏计数 / 墙钟 / 惊喜等 | 共享 defaults | **表 → 机快照 + iPhone standard；逻辑上以表为活动数据源** |
| 聊天记录 | 理想中共 suite；实际主要靠 WC | **WC 合并时一致；未同步时两端本地可不同** |
| 提醒列表 | 可共享 | **不共享** |
| Digest 配置与缓存正文 | 可共享 | **不共享** |
| 通知「点进总结」等标记 | 可共享 | **不共享** |
| LLM Keychain | 非 group | **不变** |
| Widget / Extension 共享本地数据 | 常用 group | **需恢复 group 或改架构** |

---

## 6. 续费后恢复 App Group（操作清单）

1. **Apple Developer**：为 App ID 配置 **App Groups**，勾选 `group.com.gathxr.BolaBola`（与 `Shared/AppGroupConfig.swift` 中 `suiteName` 一致）。  
2. **Xcode**：iOS 与 Watch **两个 target** → **Signing & Capabilities** → 添加 **App Groups**，勾选同一 group。  
3. **Entitlements**：在 `BolaBola iOS/BolaBola.entitlements` 与 `BolaBola Watch App/BolaBola Watch App.entitlements` 中恢复注释块 **`RESTORE_APP_GROUP_WHEN_PAID_DEV`** 所示的 `com.apple.security.application-groups` 段落（或按 Xcode 自动写回）。  
4. **代码**：全工程搜索 **`RESTORE_APP_GROUP_WHEN_PAID_DEV`**，对照 `AppGroupConfig`、`BolaSharedDefaults` 等说明复查。  

**注意**：恢复后 `resolved()` 会重新指向 **共享 suite**。此前只写在 **各端 standard** 里的数据 **不会自动合并进 group**，是否需要一次性迁移或「以某一端为准」属于产品决策，需单独设计。

---

## 7. 相关源码位置（便于跳转）

| 内容 | 路径 |
|------|------|
| Suite 名与恢复注释 | `Shared/AppGroupConfig.swift` |
| `resolved()` / 迁移 | `Shared/BolaSharedDefaults.swift` |
| 陪伴快照与 WC | `Shared/BolaWCSessionCoordinator.swift` |
| 快照键集合 | `Shared/CompanionPersistenceKeys.swift`（`wcGameStateSnapshotKeys`） |
| WC payload 键 | `Shared/WCSyncPayload.swift`（`companionSnapshot*`） |
| iPhone 合并后刷新 UI | `Notification.Name.bolaCompanionStateDidMergeFromWatch`，`BolaBola iOS/IOSRootView.swift` |

---

*文档版本：与「暂时移除 App Group + 手表游戏状态 WC 快照」实现同步；若后续增加提醒/Digest 的 WC 同步，请更新第 4、5 节。*
