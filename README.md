# KiteSim 助手 · iOS 26 原生版

安卓端功能的 SwiftUI 移植版，使用 iOS 26 Liquid Glass 系统 API。

**当前打包目标只有一个：通过云端 macOS 26 + Xcode 生成未签名 IPA。**
不再使用 xtool，不需要 Xcode.xip、Apple ID、证书、描述文件或连接 iPhone。

## 一、云端构建（推荐）

把本目录作为 GitHub 仓库根目录上传。仓库已包含：

```text
.github/workflows/build-unsigned-ipa.yml
```

在 GitHub 仓库的 **Actions → Build unsigned IPA → Run workflow** 启动构建，或推送一次提交自动触发。

流水线会：

1. 启动 `macos-26`，使用其 Xcode / iOS 26 SDK；
2. 安装 XcodeGen 并生成 `KiteSim.xcodeproj`；
3. 拉取微软官方 ONNX Runtime SwiftPM 1.24.2；
4. 用 `xcodebuild archive` 编译 Release 真机包，明确设置 `CODE_SIGNING_ALLOWED=NO`；
5. 检查主 App 不含 `_CodeSignature` 和 `embedded.mobileprovision`；
6. 按 `Payload/KiteSim.app` 标准结构压成 IPA；
7. 上传 Artifact：**`KiteSim-unsigned-ipa`**。

Artifact 内的实际文件为：

```text
KiteSim-unsigned.ipa
```

### 免费额度

- 公开仓库：标准 GitHub-hosted runner 免费。
- 私有仓库：免费账户每月有包含额度；macOS 构建按官方倍率消耗，足够日常调试。
- 不要上传 `accounts.jsonl`、账号密码、证书或描述文件。本目录当前不包含这些文件。

## 二、在 macOS 上本地构建（可选）

只需 Xcode 26+ 和 XcodeGen，不需要开发者账号：

```bash
brew install xcodegen
cd ios
bash Scripts/build_unsigned_ipa.sh
```

输出位置：

```text
build/ipa/KiteSim-unsigned.ipa
```

脚本末尾会显示 IPA 大小和 SHA-256。

## 三、工程结构

```text
ios/
├── project.yml                    XcodeGen 工程、依赖、Info.plist、禁用签名设置
├── Package.swift                  保留的 SwiftPM 清单；新 IPA 流水线不依赖 xtool
├── Scripts/
│   └── build_unsigned_ipa.sh      Archive + 未签名检查 + IPA 打包
├── .github/workflows/
│   └── build-unsigned-ipa.yml     macOS 26 云端构建
└── Sources/KiteSim/
    ├── KiteSimApp.swift           @main 入口
    ├── AppState.swift             全局状态 / 注册·登录·自检编排
    ├── Design.swift               Liquid Glass 设计系统
    ├── HTTPClient.swift           浏览器头 / 非 JSON 重试 / 代理 / 统一错误
    ├── KiteSimAPI.swift           KiteSim 接口
    ├── TempMail.swift             mail.tm 临时邮箱
    ├── CaptchaOCR.swift           ONNX Runtime 推理 + CTC 解码
    ├── Registrar.swift            注册与登录编排
    ├── Models.swift               Account / JSONL / App 资源定位
    ├── Views/                     账号、网络、关于、WKWebView 页面
    └── Resources/
        ├── common_old.onnx        ddddocr 模型（13.6MB）
        └── charset.json           CTC 字符集
```

## 四、构建注意点

- 最低系统为 **iOS 26**，因为 `glassEffect`、`GlassEffectContainer` 和玻璃按钮样式均为 iOS 26 API。
- 资源统一通过 `Bundle.main` 加载，适用于 Xcode App target；不再引用仅 SwiftPM 生成的 `Bundle.module`。
- ONNX Runtime 使用微软官方 SwiftPM 包，模型文件与安卓端一致。
- 首次云端构建会真实检查 SwiftUI、WebKit 和 ONNX Runtime 的编译/链接；若失败，应根据 Actions 日志修复，不能把 YAML 校验通过当成 IPA 已构建成功。
- 本流程只产出未签名 IPA，不包含签名、安装、续签或 App Store 发布步骤。
