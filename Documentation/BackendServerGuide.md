# BolaBola 后端服务器使用说明

## 概述

BolaBolaServer 是 BolaBola 宠物伴侣 App 的后端服务，基于 FastAPI + PostgreSQL。

**核心能力**：
- 用户认证（Sign in with Apple → Bola JWT）
- 订阅管理（App Store Server API + Webhook V2）
- AI 代理（聊天 + 语音转写，客户端不需要持有第三方 API key）
- 后台对账（定时刷新订阅状态、重试未处理的通知）

**源码位置**：`/Users/limingchendev/Documents/BolaWatch/BolaBolaServer/`

---

## 本地开发环境搭建

### 1. 启动 PostgreSQL

```bash
cd BolaBolaServer
docker compose up db -d
```

容器配置（`docker-compose.yml`）：
- 用户名：`bolabola`
- 密码：`bolabola`
- 数据库：`bolabola`
- 端口：`5432`

### 2. 配置环境变量

```bash
cp .env.example .env
```

`.env` 关键变量：

| 变量 | 说明 | 本地开发默认值 |
|------|------|----------------|
| `DATABASE_URL` | 异步数据库连接 | `postgresql+asyncpg://bolabola:bolabola@localhost:5432/bolabola` |
| `APP_ENV` | 环境标识 | `development` |
| `JWT_SECRET` | JWT 签名密钥 | `change-me-in-production` |
| `OPENROUTER_API_KEY` | OpenRouter API key | 需要填入真实 key |
| `ZHIPU_API_KEY` | 智谱 API key | 需要填入真实 key |

### 3. 运行数据库迁移

```bash
alembic upgrade head
```

创建 12 张表：users, user_sessions, devices, subscriptions, user_entitlements, app_store_notifications, pets, pet_state_snapshots, diary_entries, life_records, meal_slots, ai_request_logs

### 4. 启动服务器

```bash
uvicorn app.main:app --reload
```

- API 地址：`http://localhost:8000`
- Swagger 文档：`http://localhost:8000/docs`（可交互测试）
- ReDoc 文档：`http://localhost:8000/redoc`

### 5. 停止 PostgreSQL

```bash
docker compose down
```

数据保留在 Docker volume `pgdata` 中，下次 `docker compose up db -d` 会恢复。

---

## API 端点一览

所有端点前缀：`/api/v1`

### 健康检查

| 方法 | 路径 | 认证 | 说明 |
|------|------|------|------|
| GET | `/health` | 不需要 | 服务器状态检查 |

### 认证

| 方法 | 路径 | 认证 | 说明 |
|------|------|------|------|
| POST | `/auth/apple` | 不需要 | Apple 登录 |
| POST | `/auth/refresh` | 不需要 | 刷新 token |
| POST | `/auth/logout` | Bearer | 登出 |

### 订阅

| 方法 | 路径 | 认证 | 说明 |
|------|------|------|------|
| GET | `/subscriptions/context` | Bearer | 获取订阅上下文 + appAccountToken |
| POST | `/subscriptions/sync` | Bearer | 同步购买记录 |
| GET | `/subscriptions/status` | Bearer | 查询订阅状态 |

### Webhook

| 方法 | 路径 | 认证 | 说明 |
|------|------|------|------|
| POST | `/webhooks/apple/subscriptions` | Apple 签名 | Apple 服务器通知回调 |

### AI 代理

| 方法 | 路径 | 认证 | 说明 |
|------|------|------|------|
| POST | `/ai/v1/chat/completions` | Bearer | AI 聊天（OpenAI 兼容格式） |
| POST | `/ai/v1/audio/transcriptions` | Bearer | 语音转写（multipart 上传） |

---

## 认证流程

### 登录流程

```
1. iOS 调用 Sign in with Apple → 获取 identityToken
2. iOS 发送 POST /api/v1/auth/apple
   请求体：{ "identityToken": "...", "nonce": "..." }
3. 后端验证 Apple identityToken（JWKS + RS256）
4. 后端创建/查找用户，创建会话
5. 后端返回：
   {
     "accessToken": "eyJ...",      // JWT，1小时过期
     "refreshToken": "abc123...",  // 不透明 token，30天过期
     "user": {
       "id": "uuid",
       "appleSub": "001234.abcd...",
       "appAccountToken": "uuid"   // 给 StoreKit 2 绑定购买
     }
   }
6. iOS 存储 accessToken 和 refreshToken 到 Keychain
```

### 请求认证

所有需要认证的端点使用 Bearer token：

```
Authorization: Bearer <accessToken>
```

### Token 刷新

accessToken 过期时（HTTP 401），用 refreshToken 获取新的：

```
POST /api/v1/auth/refresh
请求体：{ "refreshToken": "abc123..." }
返回：{ "accessToken": "eyJ...", "refreshToken": "xyz789..." }
```

注意：refreshToken 每次刷新后会**轮换**（旧的立刻失效），必须存储新的。

### 登出

```
POST /api/v1/auth/logout
请求体：{ "logoutAll": false }   // true = 登出所有设备
Header：Authorization: Bearer <accessToken>
```

---

## AI 代理使用

### 聊天

请求格式和 OpenAI 完全兼容，但 model 字段使用后端路由名：

```json
POST /api/v1/ai/v1/chat/completions
Authorization: Bearer <accessToken>

{
  "model": "bola-chat-fast",
  "messages": [
    {"role": "system", "content": "你是手表宠物 Bola"},
    {"role": "user", "content": "你好呀"}
  ],
  "temperature": 0.7
}
```

**模型路由映射**：

| 路由名 | 实际模型 | 权限 |
|--------|----------|------|
| `bola-chat-fast` | gpt-4o-mini（OpenRouter） | 免费用户可用 |
| `bola-chat-quality` | claude-sonnet-4（OpenRouter） | 仅 Pro |

**每日配额**：

| 用户等级 | 聊天次数 | 语音转写次数 |
|----------|----------|-------------|
| 免费用户 | 20 次/天 | 5 次/天 |
| Pro 用户 | 500 次/天 | 50 次/天 |

### 语音转写

```
POST /api/v1/ai/v1/audio/transcriptions
Authorization: Bearer <accessToken>
Content-Type: multipart/form-data

model: bola-asr-default
file: (audio.wav 或 audio.mp3)
language: zh (可选)
```

返回：
```json
{
  "text": "你好呀",
  "language": "zh"
}
```

### 错误码

| HTTP 状态码 | error.code | 说明 |
|-------------|-----------|------|
| 400 | unknown_model | 模型名不存在 |
| 401 | - | token 无效或过期 |
| 403 | tier_denied | 免费用户请求了 Pro 模型 |
| 429 | quota_exceeded | 今日配额用完 |
| 502 | provider_error | 上游 AI 服务故障 |

---

## 订阅系统

### appAccountToken

登录后后端返回的 `appAccountToken` 是一个 UUID，需要在 StoreKit 2 购买时传入，用于把 Apple 购买记录绑定到 Bola 用户：

```swift
let purchase = try await product.purchase(options: [.appAccountToken(appAccountToken)])
```

### 同步购买

```json
POST /api/v1/subscriptions/sync
Authorization: Bearer <accessToken>

{
  "appAccountToken": "uuid-from-login",
  "originalTransactionId": "xxx",
  "productId": "com.GathXRTeam.BolaBola.pro.monthly",
  "environment": "sandbox"
}
```

### Apple Webhook

Apple 服务器通知 V2 会发到 `POST /api/v1/webhooks/apple/subscriptions`，后端自动处理订阅状态变更。无需客户端操作。

---

## 开发测试提示

### 本地测试 AI 代理

1. 在 `.env` 中填入 `OPENROUTER_API_KEY`（在 https://openrouter.ai 免费注册获取）
2. 重启服务器
3. AI 代理端点（`/ai/v1/*`）需要 Bearer token 认证，必须先通过 `/auth/apple` 登录获取 accessToken
4. 在 Swagger UI（`/docs`）中点击 🔒Authorize 按钮，输入 `Bearer <accessToken>`，然后测试 AI 端点

> 注意：`/health` 端点只验证服务器是否存活，不需要认证，也不能用来验证 AI 代理功能。
> 测试 AI 代理必须使用带认证的 `/ai/v1/chat/completions` 或 `/ai/v1/audio/transcriptions`。

### 测试 Apple 登录

需要：
- Apple 开发者账号（付费）
- Xcode 中配置 Sign in with Apple capability
- 真机或模拟器运行 iOS 端

### 运行单元测试

```bash
cd BolaBolaServer
pytest tests/ -v
```

使用 SQLite 内存数据库，不需要 PostgreSQL。

---

## 服务器架构

```
BolaBolaServer/
├── app/
│   ├── main.py           # FastAPI 应用入口
│   ├── config.py          # 配置（从 .env 加载）
│   ├── database.py        # 异步数据库引擎
│   ├── auth/              # 认证模块
│   │   ├── jwt.py         # JWT 创建/验证
│   │   └── deps.py        # FastAPI 认证依赖
│   ├── models/            # 数据库模型（12 张表）
│   ├── schemas/           # Pydantic 请求/响应模型
│   ├── services/          # 业务逻辑
│   │   ├── auth.py        # 登录、刷新、登出
│   │   ├── apple_identity.py  # Apple identityToken 验证
│   │   ├── app_store.py   # App Store Server API
│   │   ├── subscriptions.py   # 订阅 + 权益逻辑
│   │   └── reconciliation.py  # 后台对账
│   ├── ai_proxy/          # AI 代理模块
│   │   ├── proxy.py       # 代理服务（聊天 + 转写）
│   │   ├── providers/     # AI 提供商（OpenRouter/OpenAI/智谱）
│   │   ├── router.py      # 模型路由映射
│   │   ├── rate_limiter.py # 每日配额管理
│   │   ├── registry.py    # 提供商生命周期管理
│   │   └── schemas.py     # AI 请求/响应模型
│   └── api/v1/            # API 路由
│       ├── health.py
│       ├── auth.py
│       ├── subscriptions.py
│       ├── webhooks/apple.py
│       └── ai.py
├── alembic/               # 数据库迁移
└── tests/                 # 单元测试
```

---

## 实现阶段

| 阶段 | 范围 | 状态 |
|------|------|------|
| 1 | 认证 + 订阅 | ✅ 完成 |
| 1.5 | 后台对账 | ✅ 完成 |
| 2 | AI 代理（聊天 + 语音转写） | ✅ 完成 |
| 3 | 宠物云端数据 | 待开发 |
| 4 | 运维加固 | 待开发 |
