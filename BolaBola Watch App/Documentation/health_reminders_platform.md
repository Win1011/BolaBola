# 本地通知与 HealthKit — 平台限制与配置说明

实现：`ReminderScheduler.swift`、`HealthKitManager.swift`；权限文案通过 Xcode **Generated Info.plist** 的 `INFOPLIST_KEY_*` 注入。

---

## 1. 本地通知（`UserNotifications`）

- **喝水**：无可靠「身体缺水」传感器 → 使用 **固定间隔** 本地通知（默认约每 **2 小时**），用户未记录饮水时也无法推断生理状态。
- **站立 / 活动**：同样为 **提醒型**，非医学上的「你必须站立」判定；默认约每 **3 小时**。
- watchOS 后台策略严格：勿假设通知 **精确到秒** 送达；系统可能合并或延迟。
- 首次调用 `scheduleDefaultsIfAuthorized()` 会请求授权并 **移除再注册** 默认定时请求（便于后续改为用户设置）。

---

## 2. HealthKit（只读）

- **Capability**：Watch 目标需启用 **HealthKit**；仓库内使用 `BolaBola Watch App.entitlements`。
- **读取类型**：当前请求 **心率**、**步数**（可选用于扩展）。
- **心率「偏快」**：默认阈值 **100 bpm**（`heartRateAlertThreshold`），在 **`onViewAppear`** 时查询**最近样本**，超阈值则在 **App 内文字气泡** 显示一句；**非诊断、非治疗建议**。
- **后台**：不在此承诺「后台持续监听心率」。应以 **进入前台刷新** + **本地通知兜底** 为主。
- 若用户拒绝授权或未佩戴手表，可能无样本 → 不显示心率句。

---

## 3. 隐私文案（Info）

- `NSHealthShareUsageDescription`：说明读取健康数据用于 **非医疗性** 界面提示（如心率提醒句）。
- `NSUserNotificationsUsageDescription`：说明 **本地提醒**（喝水、活动等）。

---

## 4. 免责声明

本应用提供的健康相关提示仅为 **陪伴与习惯提醒**，不能替代专业医疗诊断或急救。心率、步数等数据可能存在误差或延迟。
