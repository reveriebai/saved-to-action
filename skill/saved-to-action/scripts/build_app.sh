#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SKILL_DIR="${SCRIPT_DIR:h}"
APP_SOURCE_DIR="$SKILL_DIR/assets/macos-app"
WORKSPACE=""
INSTALL=false

while (( $# > 0 )); do
  case "$1" in
    --workspace)
      WORKSPACE="$2"
      shift 2
      ;;
    --install)
      INSTALL=true
      shift
      ;;
    *)
      print -u2 "未知参数：$1"
      exit 2
      ;;
  esac
done

if [[ -z "$WORKSPACE" || ! -f "$WORKSPACE/saved-to-action.json" ]]; then
  print -u2 "请用 --workspace 指向已经初始化的 Saved to Action 工作目录"
  exit 2
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
  print -u2 "不支持的架构：$ARCH"
  exit 2
fi

SDK_PATH="$(xcrun --show-sdk-path)"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/saved-to-action-build.XXXXXX")"
trap 'rm -rf "$BUILD_ROOT"' EXIT

APP_BUNDLE="$BUILD_ROOT/Saved to Action.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
OUTPUT_DIR="$WORKSPACE/dist"
OUTPUT_APP="$OUTPUT_DIR/Saved to Action.app"
MODULE_CACHE="$BUILD_ROOT/module-cache"
CLANG_CACHE="$BUILD_ROOT/clang-cache"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE" "$CLANG_CACHE" "$OUTPUT_DIR"

xcrun swiftc \
  -O \
  -parse-as-library \
  -target "$ARCH-apple-macosx13.0" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  -Xcc "-fmodules-cache-path=$CLANG_CACHE" \
  "$APP_SOURCE_DIR"/Sources/*.swift \
  -o "$MACOS_DIR/SavedToActionDesktop"

cp "$APP_SOURCE_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$APP_SOURCE_DIR/Resources/Board.html" "$RESOURCES_DIR/Board.html"
python3 "$SCRIPT_DIR/saved_to_action.py" configure-app \
  --workspace "$WORKSPACE" \
  --output "$RESOURCES_DIR/AppConfig.json" >/dev/null
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

if [[ -e "$OUTPUT_APP" ]]; then
  rm -rf "$OUTPUT_APP"
fi
ditto --norsrc --noextattr "$APP_BUNDLE" "$OUTPUT_APP"

if $INSTALL; then
  INSTALL_DIR="$HOME/Applications"
  INSTALL_APP="$INSTALL_DIR/Saved to Action.app"
  mkdir -p "$INSTALL_DIR"
  if [[ -e "$INSTALL_APP" ]]; then
    print -u2 "安装目标已经存在：$INSTALL_APP。为避免覆盖现有 App，安装已停止。"
    exit 3
  fi
  ditto --norsrc --noextattr "$OUTPUT_APP" "$INSTALL_APP"
  python3 "$SCRIPT_DIR/saved_to_action.py" configure-app --workspace "$WORKSPACE"
  print "$INSTALL_APP"
else
  print "$OUTPUT_APP"
fi
