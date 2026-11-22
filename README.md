# 狗头军师 · iOS

把 [goutoujunshi](https://github.com/shengjidaguai-china/goutoujunshi) 这个 Skill 做成一个能侧载到 iPhone 上的原生 App：43 篇知识库离线内嵌，聊天截图直接拍照/选图，液态玻璃 UI。

Windows 上没 Xcode 也能出 IPA——用 GitHub Actions 的 macOS 机器编译，回头在 Windows 上用 Sideloadly 签名装到手机上。

---

## 它是什么

| 能力 | 说明 |
|---|---|
| **离线知识库** | 43 篇参考文档 + `SKILL.md` 行为内核全部打进 App（约 320 KB JSON），不联网也能检索 |
| **按需检索** | 中文分词 + TF-IDF，每轮挑最相关的 1–6 篇塞进上下文，不一次喂完整库 |
| **截图分析** | 相册选图 / 文件导入，长边压到 1280 再上传，气泡里的字仍看得清 |
| **聊天导出** | 支持 `.txt` `.md` `.json` `.csv`，UTF-8 与 GB18030 双解码 |
| **流式输出** | SSE 逐字返回，可中途停止 |
| **主题色** | 9 个系统色预设 + 完全自定义取色，跟着标题栏、发送键、气泡走 |
| **液态玻璃** | iOS 26 上用原生 `glassEffect` / `GlassEffectContainer`，输入框和发送键靠近会互相融合；iOS 17–25 自动降级为磨砂 + 高光描边 |
| **本地存储** | 会话存 `Documents/chat.json`，API Key 存 `UserDefaults`，都不上云 |
| **任意后端** | OpenAI 兼容协议，DeepSeek / OpenAI / OpenRouter / 硅基流动 / 局域网自建都行 |

---

## 三步出 IPA

### 1. 建仓库并推代码

在 GitHub 上新建一个仓库（**公开**最省事，私有也行——私有仓库每月有 2000 分钟免费 macOS 额度，这个项目构建约 3 分钟）。

```bash
cd goutou-ios
git init
git add .
git commit -m "goutoujunshi ios"
git branch -M main
git remote add origin https://github.com/<你的账号>/goutou-junshi-ios.git
git push -u origin main
```

> `.gitignore` 已经排除了 `build/`、`*.xcodeproj`、`Payload/`、`*.ipa`，推上去的就是纯源码。

### 2. 等 Actions 跑完

推上去后进仓库的 **Actions** 标签页，`build-ipa` 会自动开始。大约 3–5 分钟，流程是：

```
选最新 Xcode → brew install xcodegen → xcodegen generate
→ xcodebuild(无签名) → 打 Payload/*.app → zip 成 ipa → 上传 artifact
```

跑完在 **Artifacts** 里下载 `Goutoujunshi-ipa`，解压得到 `Goutoujunshi-unsigned.ipa`。

如果失败，`build-log` artifact 里有完整编译日志，把最后 60 行贴给我就能定位。

也可以手动触发：Actions → build-ipa → Run workflow。

### 3. 侧载到 iPhone

**Windows 路线（推荐 Sideloadly）**

1. 装 [iTunes](https://www.apple.com/itunes/download/win64)（**不要**装 Microsoft Store 版本）和 iCloud for Windows
2. 装 [Sideloadly](https://sideloadly.io/)
3. iPhone 用数据线连电脑，手机上点「信任此电脑」
4. 打开 Sideloadly，把 `Goutoujunshi-unsigned.ipa` 拖进去
5. Apple ID 填你的，密码建议用 [App 专用密码](https://appleid.apple.com/account/manage)（不然可能触发双重验证拦截）
6. 点 **Start**，等进度条走完
7. 手机上：**设置 → 通用 → VPN与设备管理 → 开发者 App → 信任**
8. iOS 16 以上还要开 **设置 → 隐私与安全性 → 开发者模式**，重启一次

**关于 7 天**

免费 Apple ID 签的 App 有效期 7 天，过期打不开。三个选择：

- 每 7 天重新拖一次 IPA（Sideloadly 会覆盖安装，聊天记录保留）
- 用 [AltStore](https://altstore.io/)，装 AltServer 到电脑上常开，同一 WiFi 下自动续签
- 有 $99/年的开发者账号就是 1 年

**其他路线**

- **AltStore / SideStore**：同上
- **TrollStore**：如果你的设备在支持范围内（iOS 14.0–17.0 特定版本），可以不签名直接装，永不过期
- **Mac**：Xcode 直接 `open Goutoujunshi.xcodeproj`，选真机 Run，免费账号同样 7 天

---

## 装好之后

1. 打开 App，点「还没接上模型」
2. 选一个服务商预设，或者手动填：
   - 地址：`https://api.deepseek.com/v1`（填到 `/v1` 就行，App 自己补 `/chat/completions`）
   - Key：`sk-...`
   - 模型：`deepseek-chat`、`gpt-4o`、`google/gemini-2.5-pro`……
3. 点「测试连接」，出现 `✓ 连通` 就通了
4. 回聊天页，点「填入问卷模板」或者直接讲故事

**要看截图必须用视觉模型。** `deepseek-chat` 是纯文本模型，贴图会报错或忽略。换成带 VL 的模型（`gpt-4o`、`Qwen2.5-VL`、`gemini-2.5-pro` 这类）。

---

## 液态玻璃是怎么做的

iOS 26 把 Liquid Glass 开放成了 SwiftUI 一等公民。这个项目用到三个 API：

```swift
// 1. 给任意视图套玻璃
view.glassEffect(.regular.tint(.orange).interactive(), in: .capsule)

// 2. 让相邻玻璃互相融合（输入框 + 发送键靠近时「粘」在一起）
GlassEffectContainer(spacing: 10) { ... }

// 3. 玻璃按钮样式
button.buttonStyle(.glassProminent)
```

`GlassKit.swift` 里做了两层兜底，保证不论 CI 上的 Xcode 是 25 还是 26 都能编过：

```swift
#if compiler(>=6.2)                 // Xcode 26+ 的编译器才认识 Glass 类型
if #available(iOS 26.0, *) {
    self.glassEffect(GlassKit.make(tint: tint, interactive: interactive), in: shape)
} else {
    self.legacyGlass(shape, tint: tint)   // iOS 17–25：ultraThinMaterial + 高光描边
}
#else
self.legacyGlass(shape, tint: tint)       // Xcode 25：整段玻璃代码被剔掉
#endif
```

没有背景就没有折射。`AuroraBackground` 那层暖色光斑不是装饰——玻璃需要有颜色的东西在下面，才看得出它是玻璃。

想调玻璃强度，改 `GlassKit.make` 里的 `.regular` → `.clear`（更透）或加 `tint`。

---

## 目录

```
goutou-ios/
├── project.yml                    XcodeGen 工程描述（不手写 .pbxproj）
├── Support/Info.plist             中文显示名、ATS 放行、相册权限说明
├── Sources/
│   ├── App.swift                  @main
│   ├── Models.swift               Message / Attachment
│   ├── ChatStore.swift            会话状态、流式接收、落盘
│   ├── Knowledge.swift            知识库加载 / 中文分词 / TF-IDF 检索
│   ├── LLM.swift                  OpenAI 兼容流式客户端（SSE）
│   ├── AttachmentKit.swift        图片压缩、文本文件解码
│   ├── GlassKit.swift             液态玻璃适配层 + 光斑背景
│   ├── ChatView.swift             主界面 / 空态 / 工具栏
│   ├── MessageRow.swift           气泡、Markdown、代码块、附件预览
│   ├── ComposerBar.swift          输入条、相册、文件导入
│   ├── SettingsView.swift         配置与连通性自检
│   ├── knowledge.json             构建产物（43 篇全文，320 KB）
│   └── Assets.xcassets/           图标
├── Resources/                     知识库原始 Markdown（不进 bundle）
├── tools/
│   ├── build-knowledge.mjs        重新生成 knowledge.json
│   └── make-icon.mjs              纯 Node 生成 1024 图标（无依赖）
└── .github/workflows/build-ipa.yml
```

## 更新知识库

上游仓库更新后：

```bash
git -C ../goutoujunshi pull          # 或重新 clone 上游
cp -r ../goutoujunshi/SKILL.md Resources/
cp -r ../goutoujunshi/references/* Resources/references/
node tools/build-knowledge.mjs       # 重新打包 knowledge.json
git commit -am "chore: sync knowledge base" && git push
```

Actions 会自动重新出包。图标不用动。

---

## 已知取舍

- **表格在窄屏会塌**。知识库里的 Markdown 表格走的是原文渲染，靠等宽对齐凑合看；聊天输出里的代码块是单独排版的，不受影响。
- **上下文按轮数截断**（最近 24 条）。长期档案建议直接说「把上面这些记下来」，靠 `chat.json` 里的历史承载。
- **检索是词频启发式，不是向量检索**。好处是零依赖、离线、瞬时；坏处是对「她说『随便』但我感觉不对劲」这种纯口语表述，可能命中不准。真遇到就手动在输入里点名：比如带上「依恋」「投入失衡」这些词，能显著提高召回。

---

---

开发作者：**村口架狙**

先接住情绪，再分清事实，最后给能执行的选择。
