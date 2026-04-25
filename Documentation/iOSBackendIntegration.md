# iOS 对接后端服务器设计方案

## 目标

将 iOS 端从「直连第三方 AI 服务」改为「通过 BolaBolaServer 后端代理」，并新增用户认证（Sign in with Apple）。

---

## 现状分析

### 当前 iOS 网络架构

```
┌──────────┐    API Key (Keychain)     ┌──────────────┐
│  iPhone  │ ─────────────────────────→ │ OpenAI/智谱   │
│  Watch   │ ──── WCSession ────→      │ (直连)        │
└──────────┘                           └──────────────┘
```

- `LLMClient.swift`：持有第三方 API key，直接调用 OpenAI/智谱 API
- `ConversationService.swift`：通过 `LLMClient.loadFromKeychain()` 获取配置
- `LocalLLMDevSecrets.swift`：硬编码开发用 API key
- 无用户认证、无 token 管理、无订阅管理

### 问题

1. 第三方 API key 暴露在客户端（Keychain 安全但仍可被提取）
2. 无法做服务端配额控制
3. 无法区分免费/付费用户
4. 无法统一管理 AI 提供商切换

### 目标架构

```
┌──────────┐   Bola JWT (Keychain)    ┌──────────────────┐   API Key    ┌──────────────┐
│  iPhone  │ ────────────────────────→ │ BolaBolaServer   │ ───────────→ │ OpenAI/智谱   │
│  Watch   │ ──── WCSession ────→     │ (后端代理)        │              │ (服务端调用)  │
└──────────┘                           └──────────────────┘              └──────────────┘
```

---

## 改动清单

### 新增文件

| 文件 | 位置 | 说明 |
|------|------|------|
| `BolaAPIService.swift` | `Shared/Network/` | 统一网络层：登录、token 管理、认证请求 |
| `BolaSignInView.swift` | `BolaBola iOS/Auth/` | Sign in with Apple 登录视图 |

### 修改文件

| 文件 | 说明 |
|------|------|
| `ConversationService.swift` | AI 调用从 `LLMClient` 直连改为通过 `BolaAPIService` 走后端 |
| `IOSRootView.swift` 或入口视图 | 加入登录状态判断，未登录时显示 `BolaSignInView` |
| Xcode 项目配置 | 添加 Sign in with Apple capability |

### 保留不变

| 文件 | 原因 |
|------|------|
| `LLMClient.swift` | 保留作为离线/开发 fallback，不删除 |
| `LLMModels.swift` | `OpenAICompatibleChatResponse` 等模型类型继续复用 |
| `LocalLLMDevSecrets.swift` | 保留用于开发调试，上线前清空 key |

---

## 模块详细设计

### 1. BolaAPIService（统一网络层）

**文件**：`Shared/Network/BolaAPIService.swift`
**编译目标**：iOS + Watch + Widget（但实际只在 iOS 端使用）

#### 职责

- 管理 Bola JWT token（accessToken + refreshToken）
- 自动给请求添加 `Authorization: Bearer <accessToken>` 头
- accessToken 过期时自动用 refreshToken 刷新
- 刷新时 refreshToken 轮换（旧的立刻失效）

#### 接口设计

```swift
public final class BolaAPIService: @unchecked Sendable {
    public static let shared = BolaAPIService()

    // 可配置后端地址（本地开发 vs 生产环境）
    public var baseURL: URL

    // 当前登录状态
    public var isAuthenticated: Bool

    // ── 认证 ──
    func loginWithApple(identityToken: String, nonce: String?) async throws
    func logout(logoutAll: Bool) async throws

    // ── 带认证的请求 ──
    func authenticatedRequest(_ path: String, method: String = "POST", body: Any?) async throws -> Data
    func authenticatedUpload(_ path: String, fileData: Data, filename: String, formFields: [String: String]) async throws -> Data
}
```

#### Token 存储策略

| Token | 存储位置 | Keychain Service | Keychain Account |
|-------|----------|------------------|------------------|
| accessToken | Keychain | `com.GathXRTeam.BolaBola.auth` | `accessToken` |
| refreshToken | Keychain | `com.GathXRTeam.BolaBola.auth` | `refreshToken` |

选择 Keychain 而非 UserDefaults 的原因：token 属于敏感凭证，需要加密存储。

#### 自动刷新流程

```
1. 发送请求 → 附加 Authorization: Bearer <accessToken>
2. 如果返回 401：
   a. 用 refreshToken 调用 POST /auth/refresh
   b. 存储新的 accessToken + refreshToken（旧 refreshToken 立刻失效）
   c. 用新 accessToken 重试原请求
3. 如果刷新也失败（refreshToken 也过期）：
   a. 清除本地 token
   b. 通知 UI 层显示登录界面
```

#### base URL 配置

```swift
#if DEBUG
// 模拟器用 localhost；真机需要改成本机局域网 IP（如 http://192.168.1.100:8000/api/v1）
baseURL = URL(string: "http://localhost:8000/api/v1")!
#else
baseURL = URL(string: "https://api.bolabola.com/api/v1")!
#endif
```

> **真机调试注意**：iPhone 和 Mac 需在同一局域网。将上面的 `localhost` 替换为 Mac 的局域网 IP
>（系统设置 → Wi-Fi → 详情 → IP 地址，例如 `192.168.1.100`）。
> 后端启动时用 `uvicorn app.main:app --host 0.0.0.0 --reload` 监听所有网卡。

---

### 2. BolaSignInView（登录界面）

**文件**：`BolaBola iOS/Auth/BolaSignInView.swift`
**编译目标**：仅 iOS（watchOS 不需要登录界面）

#### 职责

- 显示 Sign in with Apple 按钮
- 获取 Apple identityToken
- 调用 `BolaAPIService.loginWithApple()` 完成登录

#### 登录流程时序

```
用户点击 "Sign in with Apple"
        │
        ▼
ASAuthorizationController 返回 ASAuthorizationAppleIDCredential
        │
        ▼
提取 credential.identityToken → String
        │
        ▼
POST /api/v1/auth/apple
{
  "identityToken": "eyJ...",
  "nonce": "abc123"           // 可选，用于防重放
}
        │
        ▼
后端返回：
{
  "accessToken": "eyJ...",
  "refreshToken": "v1.xxx...",
  "user": {
    "id": "uuid",
    "appleSub": "001234.abcd...",
    "appAccountToken": "uuid"  // 重要！StoreKit 2 绑定用
  }
}
        │
        ▼
BolaAPIService 存储 token 到 Keychain
        │
        ▼
存储 user.appAccountToken 到 Keychain（后续 StoreKit 2 购买需要）
        │
        ▼
回调 onSignedIn() → UI 跳转到主界面
```

#### Xcode 配置

1. 选择项目 Target → Signing & Capabilities
2. 点击 "+ Capability"
3. 添加 "Sign in with Apple"
4. 确保 Bundle ID 为 `com.GathXRTeam.BolaBola`

#### nonce 生成（可选但推荐）

```swift
private static func randomNonce() -> String {
    let chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
    return String((0..<32).map { _ in chars.randomElement()! })
}
```

**nonce 传递规则**：Apple 在 identityToken 的 `nonce` claim 中存储的是原始 nonce 的 **SHA-256 哈希值**。
后端当前直接比较客户端传来的 nonce 与 token 中的 `nonce` claim。

因此：
- **方案 A（推荐）**：不使用 nonce。登录请求中不传 `nonce` 字段，后端跳过 nonce 校验。
- **方案 B**：客户端生成 `rawNonce`，对 `rawNonce` 做 SHA-256 得到 `hashedNonce`；
  将 `hashedNonce` 设入 `request.nonce`（Apple 会将其写入 identityToken 的 `nonce` claim）；
  同时将 `hashedNonce`（不是 `rawNonce`）传给后端。这样后端比较的值与 token 中的一致。

```
rawNonce (随机字符串)
  │
  ├─ SHA-256 → hashedNonce → 传给 request.nonce → Apple 写入 identityToken.nonce
  │
  └─ hashedNonce → 传给后端 POST /auth/apple 的 nonce 字段
                                          │
                                          ▼
                                后端比较 identityToken.nonce == 请求 nonce ✔
```

---

### 3. ConversationService 改造

**文件**：`Shared/LLM/ConversationService.swift`
**编译目标**：iOS + Watch

> **Watch/iPhone 边界规则**：Watch 不直接调用后端 API。所有后端请求由 iPhone 发起。
> ConversationService 中调用 `BolaAPIService` 的代码只在 iPhone 侧执行；
> Watch 端的语音请求通过 WCSession 将音频文件传给 iPhone，iPhone 调后端转写 + 聊天后将结果回传 Watch。
> `BolaAPIService` 虽然编译进 Watch target（Shared/），但 Watch 端不应直接调用其网络方法。

#### 核心改动

将 AI 调用从 `LLMClient` 直连改为通过 `BolaAPIService` 代理。

##### replyToUser（文字聊天）

```swift
// ── 旧代码 ──
let client = try LLMClient.loadFromKeychain()
let rawReply = try await client.chatCompletion(messages: messages)

// ── 新代码 ──
let api = BolaAPIService.shared
guard api.isAuthenticated else {
    throw LLMClientError.missingConfiguration
}
let body: [String: Any] = [
    "model": "bola-chat-fast",
    "messages": messages.map { ["role": $0.role, "content": $0.content] },
    "temperature": 0.7
]
let data = try await api.authenticatedRequest("/ai/v1/chat/completions", body: body)
let decoded = try JSONDecoder().decode(OpenAICompatibleChatResponse.self, from: data)
let rawReply = decoded.choices?.first?.message?.content?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
```

##### replyToUserFromRecordedAudio（语音转文字 + 聊天）

```swift
// ── 旧代码 ──
let client = try LLMClient.loadFromKeychain()
let utterance = try await client.transcribeAudio(fileURL: fileURL)
let reply = try await replyToUser(utterance: utterance, companionValue: companionValue)

// ── 新代码 ──
let api = BolaAPIService.shared
guard api.isAuthenticated else {
    throw LLMClientError.missingConfiguration
}
let fileData = try Data(contentsOf: fileURL)
let data = try await api.authenticatedUpload(
    "/ai/v1/audio/transcriptions",
    fileData: fileData,
    filename: fileURL.lastPathComponent,
    formFields: ["model": "bola-asr-default"]
)
let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let utterance = json["text"] as? String ?? ""
let reply = try await replyToUser(utterance: utterance, companionValue: companionValue)
```

#### 后端模型路由名

iOS 端发送的 `model` 字段使用后端定义的路由名，而非原始模型名：

| 场景 | 路由名 | 实际模型 | 权限 |
|------|--------|----------|------|
| 日常聊天 | `bola-chat-fast` | gpt-4o-mini | 免费 |
| 高质量聊天 | `bola-chat-quality` | claude-sonnet-4 | Pro |
| 语音转写 | `bola-asr-default` | glm-asr-2512 | 免费 |

#### 错误处理

```swift
do {
    let data = try await api.authenticatedRequest(...)
} catch BolaAPIError.httpError(403, _) {
    // 免费用户请求了 Pro 模型 → 降级到 bola-chat-fast
} catch BolaAPIError.httpError(429, _) {
    // 配额用完 → 显示提示
} catch BolaAPIError.httpError(502, _) {
    // 上游 AI 故障 → 使用 templateReply fallback
} catch BolaAPIError.notAuthenticated {
    // 未登录 → 显示登录界面
}
```

#### Fallback 策略

当后端不可用时的降级策略，按环境区分：

```swift
func replyToUser(utterance: String, companionValue: Int) async throws -> String {
    if BolaAPIService.shared.isAuthenticated {
        // 走后端代理
        return try await replyViaBackend(...)
    }

    #if DEBUG
    // DEBUG only：直连第三方 API（开发调试用，LLMClient 需要本地 API key）
    // 生产环境绝不走此路径——第三方 key 不应出现在 App Store 包中
    return try await replyViaLLMClient(...)
    #else
    // 生产环境：后端不可用时使用本地模板回复（templateReply），不暴露第三方 key
    return ConversationService.templateReply(utterance: utterance, companionValue: companionValue)
    #endif
}
```

---

### 4. 登录状态与 UI 集成

**文件**：`BolaBola iOS/App/IOSRootView.swift`（或 App 入口）

#### 登录状态判断

```swift
struct IOSRootView: View {
    @AppStorage("isLoggedIn") private var isLoggedIn = false

    var body: some View {
        if isLoggedIn && BolaAPIService.shared.isAuthenticated {
            // 主界面（现有的 Analysis / Home / Chat tabs）
            MainTabView()
        } else {
            // 登录界面
            BolaSignInView {
                isLoggedIn = true
            }
        }
    }
}
```

#### Watch 端

Watch 不直接调用后端 API。登录状态通过 WCSession 从 iPhone 同步：

```
iPhone 登录成功 → WCSession.updateApplicationContext(["isLoggedIn": true])
Watch 收到 → 显示正常界面
iPhone 登出 → WCSession.updateApplicationContext(["isLoggedIn": false])
Watch 收到 → 显示"请在 iPhone 上登录"提示
```

---

### 5. appAccountToken 与 StoreKit 2

登录成功后，后端返回的 `appAccountToken`（UUID）需要保存，后续购买订阅时传入 StoreKit 2：

```swift
// 登录成功后保存
KeychainHelper.set(
    appAccountToken.uuidString,
    service: "com.GathXRTeam.BolaBola.auth",
    account: "appAccountToken"
)

// 购买时使用
let token = KeychainHelper.get(service: "com.GathXRTeam.BolaBola.auth", account: "appAccountToken")
let uuid = UUID(uuidString: token)!
let purchase = try await product.purchase(options: [.appAccountToken(uuid)])
```

---

## 数据流对比

### 聊天（改动前）

```
用户输入 → ConversationService → LLMClient.loadFromKeychain()
→ URLSession POST https://open.bigmodel.cn/api/paas/v4/chat/completions
→ Authorization: Bearer <zhipu-api-key>
→ 返回 AI 回复
```

### 聊天（改动后）

```
用户输入 → ConversationService → BolaAPIService.shared
→ URLSession POST http://localhost:8000/api/v1/ai/v1/chat/completions
→ Authorization: Bearer <bola-access-token>
→ 后端验证 token + 配额 → 后端调用 OpenRouter/智谱
→ 返回 AI 回复
```

### 语音转写（改动前）

```
Watch 录音 → iPhone 通过 WCSession 获取文件
→ LLMClient.transcribeAudio → POST https://open.bigmodel.cn/.../audio/transcriptions
→ Authorization: Bearer <zhipu-api-key>
→ 返回文字
```

### 语音转写（改动后）

```
Watch 录音 → iPhone 通过 WCSession 获取文件
→ BolaAPIService.authenticatedUpload → POST .../ai/v1/audio/transcriptions
→ Authorization: Bearer <bola-access-token>
→ 后端验证 token + 配额 → 后端调用智谱 ASR
→ 返回文字
```

---

## 实施顺序

### Phase A：网络层 + 登录（必须先做）

1. 创建 `Shared/Network/BolaAPIService.swift`
2. 创建 `BolaBola iOS/Auth/BolaSignInView.swift`
3. Xcode 添加 Sign in with Apple capability
4. 在入口视图集成登录判断
5. **测试**：能登录、能刷新 token、能登出

### Phase B：AI 代理对接

1. 改造 `ConversationService.replyToUser` 走后端
2. 改造 `ConversationService.replyToUserFromRecordedAudio` 走后端
3. 添加错误处理（403 降级、429 提示、502 fallback）
4. **测试**：聊天和语音转写都能走后端完成

### Phase C：订阅对接（后续）

1. 集成 StoreKit 2
2. 用 `appAccountToken` 绑定购买
3. 调用 `/subscriptions/sync` 同步购买
4. 调用 `/subscriptions/context` 获取权益
5. 根据权益切换免费/Pro 模型

---

## Keychain 使用汇总

改动后的 Keychain 结构：

| Service | Account | 内容 | 新增？ |
|---------|---------|------|--------|
| `com.GathXRTeam.BolaBola.auth` | `accessToken` | Bola JWT accessToken | ✅ 新增 |
| `com.GathXRTeam.BolaBola.auth` | `refreshToken` | Bola 不透明 refreshToken | ✅ 新增 |
| `com.GathXRTeam.BolaBola.auth` | `appAccountToken` | StoreKit 2 绑定 UUID | ✅ 新增 |
| `com.GathXRTeam.BolaBola.llm` | `apiKey` | 第三方 API key | 保留（开发用） |
| `com.GathXRTeam.BolaBola.llm` | `baseURL` | 第三方 API 地址 | 保留（开发用） |
| `com.GathXRTeam.BolaBola.llm` | `modelId` | 模型名 | 保留（开发用） |
| `com.GathXRTeam.BolaBola.llm` | `authBearer` | Bearer 开关 | 保留（开发用） |

上线后 `com.GathXRTeam.BolaBola.llm` 下的条目可以清空，所有 AI 调用走后端。

---

## 安全注意事项

1. **accessToken 不要存 UserDefaults**：JWT 可被读取，必须存 Keychain
2. **refreshToken 轮换后立刻更新**：旧的 refreshToken 在服务端已失效，必须用新的替换
3. **HTTPS only**：生产环境必须使用 HTTPS，否则 Bearer token 可被中间人截获
4. **不要在 URL 或日志中输出 token**：token 只出现在 Authorization header 中
5. **Watch 不直接调后端**：所有后端请求由 iPhone 发起，Watch 通过 WCSession 获取结果

---

## 测试计划

### 本地集成测试

1. 启动后端：`docker compose up db -d && uvicorn app.main:app --reload`
2. 在 `.env` 中填入 `OPENROUTER_API_KEY`
3. iOS 真机运行，Sign in with Apple 登录
4. 发送聊天消息，验证走后端代理成功
5. 录音转写，验证走后端代理成功
6. 等待 accessToken 过期（或手动设短过期时间），验证自动刷新
7. 登出，验证 token 清除

### 模拟后端不可用

1. 停止后端服务器
2. 尝试聊天
   - DEBUG 模式：fallback 到 `LLMClient` 直连（需要本地配置第三方 API key）
   - RELEASE 模式：fallback 到 `templateReply`（本地模板回复，不调用任何 API）
3. 重启后端，验证自动恢复走后端

### 错误场景

1. 免费用户请求 `bola-chat-quality` → 应返回 403
2. 超过每日配额 → 应返回 429
3. 网络断开 → 应显示错误提示
4. Apple 登录失败 → 应显示重试选项
