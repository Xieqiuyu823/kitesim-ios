#!/usr/bin/env bash
set -euo pipefail

# 在 macOS + Xcode 26+ 上构建真正的未签名 IPA。
# 不需要 Apple ID、证书、描述文件或开发者账号。
#
# 仓库只保存文本源码；两个 OCR 资源（二进制模型 + 字符表）在构建时
# 从 ddddocr 官方仓库获取，并用本项目原始文件的哈希严格校验字节一致。

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
ARCHIVE_PATH="$BUILD_DIR/KiteSim.xcarchive"
OUTPUT_DIR="$BUILD_DIR/ipa"
IPA_PATH="$OUTPUT_DIR/KiteSim-unsigned.ipa"

RES_DIR="$ROOT/Sources/KiteSim/Resources"
MODEL_PATH="$RES_DIR/common_old.onnx"
CHARSET_PATH="$RES_DIR/charset.json"

MODEL_SHA256="b8f2ad9cbc1f2e3922a6cb9459e30824e7e2467f3fb4fd61420640e34ea0bf68"
CHARSET_JOINED_SHA256="2ad1d606078ede388943ef28b2cab3ce2ee50f81d42ff275572a69a814d136f0"

cd "$ROOT"

echo "==> 检查构建环境"
command -v xcodebuild >/dev/null
command -v xcodegen >/dev/null
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version

mkdir -p "$RES_DIR" "$BUILD_DIR"

echo "==> 准备 OCR 模型（13.6MB 二进制）"
if [[ ! -f "$MODEL_PATH" ]]; then
  MODEL_TMP="$MODEL_PATH.download"
  rm -f "$MODEL_TMP"
  curl -fL --retry 3 --connect-timeout 30 --max-time 600 \
    "https://raw.githubusercontent.com/sml2h3/ddddocr/master/ddddocr/common_old.onnx" \
    -o "$MODEL_TMP"
  echo "$MODEL_SHA256  $MODEL_TMP" | shasum -a 256 -c -
  mv "$MODEL_TMP" "$MODEL_PATH"
fi

echo "==> 准备 OCR 字符表（由官方 CHARSET_OLD 重建）"
if [[ ! -f "$CHARSET_PATH" ]]; then
  CHARSETS_PY="$BUILD_DIR/charsets.py"
  rm -f "$CHARSETS_PY"
  curl -fL --retry 3 --connect-timeout 30 --max-time 300 \
    "https://raw.githubusercontent.com/sml2h3/ddddocr/master/ddddocr/charsets.py" \
    -o "$CHARSETS_PY"
  python3 - "$CHARSETS_PY" "$CHARSET_PATH" "$CHARSET_JOINED_SHA256" <<'PY'
import ast, hashlib, json, sys

src_path, out_path, expect = sys.argv[1], sys.argv[2], sys.argv[3]
tree = ast.parse(open(src_path, encoding="utf-8").read())
charset = None
for node in tree.body:
    if isinstance(node, ast.Assign) and any(
        getattr(t, "id", "") == "CHARSET_OLD" for t in node.targets
    ):
        charset = ast.literal_eval(node.value)
        break
if charset is None:
    sys.exit("未在 charsets.py 中找到 CHARSET_OLD")

digest = hashlib.sha256("".join(charset).encode("utf-8")).hexdigest()
if digest != expect:
    sys.exit(f"字符表校验失败: {digest} != {expect}")

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(charset, fh, ensure_ascii=False, separators=(",", ":"))
print(f"字符表已生成: {len(charset)} 项, sha256={digest}")
PY
fi

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> 解析 Swift Package 依赖"
xcodebuild \
  -resolvePackageDependencies \
  -project "$ROOT/KiteSim.xcodeproj" \
  -scheme KiteSim \
  -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages"

echo "==> Archive（禁用签名）"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
  -project "$ROOT/KiteSim.xcodeproj" \
  -scheme KiteSim \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER=

APP_PATH="$ARCHIVE_PATH/Products/Applications/KiteSim.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "错误：未找到 $APP_PATH" >&2
  exit 1
fi
if [[ ! -f "$APP_PATH/KiteSim" ]]; then
  echo "错误：App 主程序不存在" >&2
  exit 1
fi
if [[ -d "$APP_PATH/_CodeSignature" ]]; then
  echo "错误：主 App 意外包含代码签名目录" >&2
  exit 1
fi
if [[ -f "$APP_PATH/embedded.mobileprovision" ]]; then
  echo "错误：主 App 意外包含描述文件" >&2
  exit 1
fi

echo "==> 校验 OCR 资源已打入 App"
for f in common_old.onnx charset.json; do
  if ! find "$APP_PATH" -maxdepth 2 -name "$f" | grep -q .; then
    echo "错误：App 包内缺少资源 $f" >&2
    exit 1
  fi
done

echo "==> 校验 App 图标已编译进 Assets.car"
if [[ ! -f "$APP_PATH/Assets.car" ]]; then
  echo "错误：App 包内缺少 Assets.car（图标未编译）" >&2
  exit 1
fi
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP_PATH/Info.plist" 2>/dev/null || true)"
if [[ "$ICON_NAME" != "AppIcon" ]]; then
  echo "错误：Info.plist 缺少 CFBundleIconName=AppIcon（实际：'$ICON_NAME'）" >&2
  exit 1
fi

echo "==> 打包标准未签名 IPA"
rm -rf "$OUTPUT_DIR/Payload"
mkdir -p "$OUTPUT_DIR/Payload"
cp -R "$APP_PATH" "$OUTPUT_DIR/Payload/KiteSim.app"
rm -f "$IPA_PATH"
(
  cd "$OUTPUT_DIR"
  zip -qry "$(basename "$IPA_PATH")" Payload
)

echo "==> 构建完成"
ls -lh "$IPA_PATH"
shasum -a 256 "$IPA_PATH"
