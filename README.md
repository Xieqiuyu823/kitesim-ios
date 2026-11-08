# KiteSim 助手 · iOS 26 原生版

安卓端功能的 SwiftUI 移植版，使用 iOS 26 Liquid Glass 系统 API。

**打包目标只有一个：通过云端 macOS + Xcode 生成未签名 IPA。**
不使用 xtool，不需要 Xcode.xip、Apple ID、证书、描述文件或连接 iPhone。

---

## 一、当前状态（已实测构建成功）

| 项 | 值 |
|---|---|
| 仓库 | <https://github.com/Xieqiuyu823/kitesim-ios> |
| 流水线 | `.github/workflows/build-unsigned-ipa.yml`（push 到 `main` 自动触发） |
| 成功运行 | run #2，`success`，耗时约 1 分半 |
| 构建机 | `macos-26`，**Xcode 26.6 (17F113)**，**iPhoneOS 26.5 SDK** |
| 产物 | `KiteSim-unsigned.ipa`，**14,217,836 字节** |
| SHA-256 | `e25e789960abb23ef4a19cce3039135cc4d485bf740e0eca18fe59806fe9e977` |
| Release | <https://github.com/Xieqiuyu823/kitesim-ios/releases/tag/unsigned-2> |

流水线内置的自检在失败时会中断构建：

1. 主 `.app` 不含 `_CodeSignature`；
2. 主 `.app` 不含 `embedded.mobileprovision`；
3. `common_old.onnx` 与 `charset.json` 确实位于 App 包内（最大 2 层目录）。

## 二、怎么重新构建

**方式 A：改代码后推送**

```bash
git clone https://github.com/Xieqiuyu823/kitesim-ios.git
cd kitesim-ios
git commit -am "your change"
git push origin main          # 自动触发构建
```

**方式 B：GitHub 网页手动触发**

进入仓库 **Actions → Build unsigned IPA → Run workflow**。

构建成功后，Release 里直接给出 IPA；Actions Artifact 里也有一份 `KiteSim-unsigned-ipa`。

> 构建会消耗 GitHub Actions 额度。公开仓库的标准 runner 免费，私有仓库按 macOS 倍率（10×）计费。

## 三、两个 OCR 资源不入库

仓库只保存文本源码，两个 OCR 资源在构建时下载并**按本项目原始文件的哈希校验**：

| 资源 | 来源 | 校验 |
|---|---|---|
| `common_old.onnx`（13.6MB） | `sml2h3/ddddocr` 官方仓库 | SHA-256 `b8f2ad9c…ea0bf68` |
| `charset.json`（8210 项） | 由 `ddddocr/charsets.py` 的 `CHARSET_OLD` 重建 | 拼接串 SHA-256 `2ad1d606…d136f0` |

两个值都已与安卓端资源逐字节比对一致，因此 iOS 识别结果与安卓端相同。
这样既避免把 13.6MB 二进制塞进仓库，也保证任何人能复现同一份资源。

## 四、工程结构

```text
ios/
├── project.yml                    XcodeGen 工程、ORT 依赖、Info.plist、禁用签名
├── Scripts/build_unsigned_ipa.sh  资源准备 + Archive + 未签名校验 + 打包 IPA
├── .github/workflows/
│   └── build-unsigned-ipa.yml     macos-26 云端构建，成功发 Release，失败开 Issue 贴日志
├── Package.swift                  早期 xtool/SwiftPM 清单，当前流水线不使用
├── xtool.yml                      早期 xtool 配置，当前流水线不使用
└── Sources/KiteSim/
    ├── KiteSimApp.swift           @main 入口
    ├── AppState.swift             全局状态 / 注册·登录·自检编排
    ├── Design.swift               Liquid Glass 设计系统
    ├── HTTPClient.swift           浏览器头 / 非 JSON 重试 / 代理 / 统一错误
    ├── KiteSimAPI.swift           KiteSim 接口（**密码明文提交**）
    ├── TempMail.swift             mail.tm 临时邮箱（含限流重试）
    ├── CaptchaOCR.swift           ONNX Runtime 推理 + CTC 解码
    ├── Registrar.swift            注册与登录编排
    ├── Models.swift               Account / JSONL / 资源定位
    └── Views/                     账号、网络、关于、WKWebView
```

`Resources/` 由构建脚本在编译前填充，因此仓库里看不到这两个文件。

## 五、构建注意点

- 最低系统 **iOS 26**：`glassEffect` / `GlassEffectContainer` / 玻璃按钮样式都是 iOS 26 API。
- 资源统一通过 `Bundle.main` 加载，不再引用只有 SwiftPM 才生成的 `Bundle.module`。
- ONNX Runtime 用微软官方 SPM 包 1.24.2，`binaryTarget` 分发 XCFramework，实测在本流水线下**可正常链接**。
- 已修复的 iOS 26 适配问题：`WKHTTPCookieStore.deleteCookie(_:completionHandler:)` 在 iOS 26 SDK 更名为 `delete(_:completionHandler:)`。
- 只产出未签名 IPA，不包含签名、安装、续签或 App Store 发布步骤。
