<div align="center">

# PhoneClaw

**你的手机，你的 AI Agent，完全在本地。**

[English](README_EN.md) · [报告问题](https://github.com/kellyvv/phoneclaw/issues) · [功能建议](https://github.com/kellyvv/phoneclaw/issues)

</div>

---

PhoneClaw 是一个运行在 iPhone 上的本地 AI Agent。它不联网、不上传数据、不依赖任何云服务——所有推理完全在设备内完成。

你说一句话，它自动判断意图、调用对应能力，直接操作设备。没有弹窗，没有授权确认，静默完成。

## 能做什么

### 🗓️ 日历 · 提醒 · 通讯录

对着 PhoneClaw 说：

> "明天下午两点，在高新园开个会"

→ 自动创建日历事项，填入时间和地点。

> "帮我存一下王总的电话 138xxxx，字节跳动的"

→ 通讯录里静默写入一个带公司名的联系人。

> "提醒我今晚八点发架构图"

→ 提醒事项准时弹出通知。

### 📋 剪贴板 · 设备信息 · 文本处理

快速读写剪贴板、查询设备信息、执行文本转换，无需切换 App。

### 🖼️ 看图理解

拍照或选图，直接询问图片内容。

### 🧩 自定义能力（Skill 系统）

用一个 Markdown 文件定义新能力，无需改代码，应用内热更新即刻生效。

---

## 隐私承诺

| | PhoneClaw | 云端 AI |
|--|--|--|
| 联网请求 | ❌ 从不 | ✅ 必须 |
| 数据上传 | ❌ 从不 | ✅ 每次对话 |
| 离线可用 | ✅ 完全 | ❌ 不行 |
| 数据归属 | 你自己 | 服务商 |

---

## 快速开始

### 环境要求

- iPhone（A16 芯片及以上；E4B 模型需要 A17 Pro）
- Xcode 16+，iOS 17.0+
- CocoaPods：`gem install cocoapods`

### 第一步：选择并下载模型

模型放在项目根目录的 `Models/` 文件夹下，**放什么就支持什么，不需要两个都放**。

**推荐 · E2B（约 1.5 GB，适合所有 A16+ 设备）**
```
Models/
└── gemma-4-e2b-it-4bit/     ← 从 Hugging Face 下载 mlx-community/gemma-4-2b-it-4bit
```

**进阶 · E4B（约 3 GB，需要 iPhone 15 Pro 及以上）**
```
Models/
└── gemma-4-e4b-it-4bit/     ← 从 Hugging Face 下载 mlx-community/gemma-4-4b-it-4bit
```

> `Models/` 已加入 `.gitignore`，模型文件不会上传到仓库。

### 第二步：安装依赖并打开

```bash
pod install
open PhoneClaw.xcworkspace
```

> ⚠️ 必须打开 `.xcworkspace`，不要直接打开 `.xcodeproj`

### 第三步：签名并运行

1. Xcode 选择 **PhoneClaw** Target → **Signing & Capabilities**
2. 填入你的 **Apple ID Team**
3. 修改 **Bundle Identifier**（如 `com.yourname.phoneclaw`）
4. USB 连接 iPhone，按 **⌘R**

首次安装需信任证书：**设置 → 通用 → VPN 与设备管理 → 信任**

---

## 内置能力

| 能力 | 说明 |
|------|------|
| 📅 日历 | 创建日历事项，支持标题、时间、地点 |
| ⏰ 提醒事项 | 创建提醒，到时间自动推送通知 |
| 👤 通讯录 | 新建或更新联系人，按手机号自动去重 |
| 📋 剪贴板 | 读取和写入系统剪贴板 |
| 📱 设备信息 | 查询设备名称、系统版本、内存等 |
| 🔤 文本工具 | 哈希计算、文本翻转等 |

---

## 添加自定义能力

在设备的 App 数据目录下创建一个 `SKILL.md` 文件即可，应用内重载后立即生效：

```
ApplicationSupport/PhoneClaw/skills/<能力名>/SKILL.md
```

```yaml
---
name: 我的能力
description: '简单描述这个能力做什么'
version: "1.0.0"
icon: star
disabled: false

triggers:
  - 关键词

allowed-tools:
  - my-tool-name
---

# 能力说明

告诉 AI 在什么情况下使用这个能力，以及如何调用工具。
```

需要调用原生 iOS API 的工具，在 `Skills/ToolRegistry.swift` 中注册即可。

---

## License

MIT — 自由使用、修改和分发。
