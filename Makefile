# ============================================================
#  Any Calculator — Tauri (Vue + Vite + Rust)  Makefile
# ============================================================

.PHONY: help typecheck check dev dev-android dev-ios build build-debug build-android build-android-debug build-ios run-ios ios-rust ios-xcode ios-doctor ios-pair ios-device-build ios-device-build-release ios-device-deploy ios-device-deploy-release ios-deploy-legacy ios-ipa-install release clean clean-rust clean-frontend clean-android clean-ios clean-all

help:
	@echo "Any Calculator — 可用目标:"
	@echo ""
	@echo "  代码检查:"
	@echo "    make typecheck         TypeScript 类型检查 (vue-tsc)"
	@echo "    make check             类型检查 + 前端构建 (快速验证)"
	@echo ""
	@echo "  开发调试:"
	@echo "    make dev              启动桌面开发模式 (热更新)"
	@echo "    make dev-android      启动 Android 开发模式"
	@echo "    make dev-ios          启动 iOS 模拟器开发模式"
	@echo ""
	@echo "  构建发布:"
	@echo "    make build            桌面 Release 构建 (macOS .dmg)"
	@echo "    make build-debug      桌面 Debug 构建"
	@echo "    make build-android    Android Release APK/AAB"
	@echo "    make build-android-debug  Android Debug (免签名)"
	@echo "    make build-ios        iOS Release IPA (Archive 导出)"
	@echo "    make run-ios          启动 iOS 真机开发模式 (需 USB 连接 iPhone)"
	@echo "    make release          一键发布 (check → 桌面 + Android + iOS)"
	@echo ""
	@echo "  iOS 专用:"
	@echo "    make ios-rust         仅编译 Rust → iOS (aarch64-apple-ios)"
	@echo "    make ios-xcode        在 Xcode 中打开 iOS 项目"
	@echo ""
	@echo "  iOS 真机直连 (绕过 Xcode GUI，解决连接报错):"
	@echo "    make ios-doctor       诊断 iOS 开发环境 (CoreDevice 原生检测)"
	@echo "    make ios-pair         设备连接修复 (无需 lockdown 配对)"
	@echo "    make ios-device-build    xcodebuild 构建 .app (Debug, 不部署)"
	@echo "    make ios-device-build-release  xcodebuild 构建 .app (Release)"
	@echo "    make ios-device-deploy    ★ 一键构建+部署 (devicectl 原生)"
	@echo "    make ios-device-deploy-release  构建 Release + 部署到真机"
	@echo "    make ios-deploy-legacy  备用方案 (ios-deploy, 需 Xcode 配对)"
	@echo "    make ios-ipa-install IPA=path   将指定 IPA 安装到真机"
	@echo ""
	@echo "  清理:"
	@echo "    make clean            清理所有构建产物"
	@echo "    make clean-rust       清理 Rust target/"
	@echo "    make clean-frontend   清理前端 dist/ node_modules/"
	@echo "    make clean-android    清理 Android 构建产物"
	@echo "    make clean-ios        清理 iOS 构建产物 + Externals"
	@echo "    make clean-all        深度清理 (含 node_modules)"
	@echo ""

# ==================== 代码检查 ====================

typecheck:
	@echo "=== TypeScript 类型检查 ==="
	npx vue-tsc --noEmit
	@echo "=== 类型检查通过 ==="

check: typecheck
	@echo "=== 前端构建 (Vite) ==="
	npm run build
	@echo "=== 检查全部通过 ==="

# ==================== 开发调试 ====================

dev:
	npm run tauri dev

dev-android:
	npm run tauri android dev

dev-ios:
	npm run tauri ios dev

# ==================== 构建 ====================

build:
	npm run tauri build

build-debug:
	npm run tauri build -- --debug

# Android Release 构建（签名需在 src-tauri/gen/android/ 下配置 key.properties）
build-android:
	npm run tauri android build

build-android-debug:
	npm run tauri android build -- --debug

# iOS Release 构建 — 生成 IPA (Archive 导出)
build-ios:
	@echo "=== 构建 iOS Release IPA ==="
	npm run tauri ios build
	@echo "=== iOS IPA 已生成 ==="

# iOS 直连真机部署 — iPhone 通过 USB 连接并解锁
run-ios:
	@echo "=== 启动 iOS 真机开发模式 ==="
	npx tauri ios dev
	@echo "=== iOS 开发模式已启动 ==="

# 手动打开 Xcode（不自动部署），Product → Destination → 选 iPhone → Cmd+R
ios-xcode:
	@echo "=== 打开 Xcode iOS 项目 ==="
	open -a Xcode src-tauri/gen/apple/calculator-tauri.xcodeproj

ios-rust:
	@echo "=== 编译 Rust for iOS (aarch64-apple-ios) ==="
	cd src-tauri && cargo build --target aarch64-apple-ios
	@echo "=== Rust iOS 编译完成 ==="

# ==================== iOS 真机直连 (绕过 Xcode GUI) ====================
# 核心思路:
#   构建: xcodebuild 命令行 (无需 Xcode GUI)
#   部署: devicectl (Apple CoreDevice 原生, 不需要 lockdown 配对)
#   备用: ios-deploy (传统 lockdown 方式, 需 Xcode 配对)

IOS_PROJ    := src-tauri/gen/apple/calculator-tauri.xcodeproj
IOS_SCHEME  := calculator-tauri_iOS
IOS_DST     := generic/platform=iOS
PROJ_ROOT   := $(shell pwd)

# === 诊断 ===
ios-doctor:
	@echo "========== iOS 开发环境诊断 =========="
	@echo ""
	@echo "[1/5] 必要工具检查..."
	@command -v xcodebuild >/dev/null && echo "  ✅ xcodebuild: $$(xcodebuild -version | head -1)" || echo "  ❌ xcodebuild 未找到"
	@command -v ios-deploy >/dev/null   && echo "  ✅ ios-deploy: $$(ios-deploy --version)" || echo "  ⚠️  ios-deploy 未安装 (备用, 非必需)"
	@echo ""
	@echo "[2/5] CoreDevice 设备检测 (Apple 原生)..."
	@DEVCOUNT=$$(xcrun devicectl list devices 2>/dev/null | grep -c -i 'iphone\|ipad'); \
	if [ "$$DEVCOUNT" -gt 0 ]; then \
		echo "  ✅ CoreDevice 检测到 $$DEVCOUNT 台设备:"; \
		xcrun devicectl list devices 2>/dev/null | grep -i 'iphone\|ipad' | while read line; do echo "     $$line"; done; \
	else \
		echo "  ❌ CoreDevice 未检测到设备"; \
		echo "     请确保: 1) USB 已连接  2) 设备已解锁  3) 已信任此电脑"; \
	fi
	@echo ""
	@echo "[3/5] Xcode 项目..."
	@if [ -d "$(IOS_PROJ)" ]; then \
		echo "  ✅ $(IOS_PROJ)"; \
	else \
		echo "  ❌ 项目不存在，请先运行: npx tauri ios init"; \
	fi
	@echo ""
	@echo "[4/5] Rust iOS target..."
	@rustup target list --installed | grep -q aarch64-apple-ios && echo "  ✅ aarch64-apple-ios" || echo "  ❌ 未安装 → rustup target add aarch64-apple-ios"
	@echo ""
	@echo "[5/5] 签名证书 (Development)..."
	@security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development" && echo "  ✅ 找到开发证书" || echo "  ⚠️  未找到开发证书，请在 Xcode 中配置签名"
	@echo ""
	@echo "=========================================="

# === 配对设备 (一次性, 配对后永久生效) ===
ios-pair:
	@echo "========== iOS 设备配对 (一次性操作) =========="
	@echo ""
	@echo "🔍 当前设备状态:"
	@xcrun devicectl list devices 2>/dev/null | grep -iE 'iphone|ipad' || echo "   (未检测到设备)"
	@echo ""
	@echo "═══════════════════════════════════════════"
	@echo "  📌 首次配对 (每个设备只需做一次, 约 30 秒):"
	@echo ""
	@echo "  1. 打开 Xcode (只需打开, 不需要打开项目)"
	@echo "     open -a Xcode"
	@echo ""
	@echo "  2. 菜单: Window → Devices and Simulators"
	@echo "     (快捷键: Cmd+Shift+2)"
	@echo ""
	@echo "  3. 解锁设备 (iPhone/iPad), 插入 USB 线"
	@echo ""
	@echo "  4. Xcode 设备列表会显示该设备"
	@echo "     等待状态变为「已配对」即可"
	@echo ""
	@echo "  5. 关闭 Xcode, 以后永远不需要再打开!"
	@echo "     make ios-device-deploy 直接可用"
	@echo "═══════════════════════════════════════════"
	@echo ""
	@echo "  💡 CoreDevice 配对是永久的 (不像 lockdown 经常过期)"
	@echo "     支持多设备: iPhone / iPad 均可"
	@echo "     默认优先部署 iPhone, 无 iPhone 则用 iPad"
	@echo "=========================================="

# === 仅构建 .app (不部署) ===
# 注意: 裸 xcodebuild 无法正确触发 Tauri 构建脚本 (需要 dev server addr)
# 使用 tauri ios build --debug 来正确构建
ios-device-build:
	@echo "=== Tauri iOS Debug 构建 ==="
	npx tauri ios build --debug
	@echo "=== 构建完成 ==="

ios-device-build-release:
	@echo "=== Tauri iOS Release 构建 ==="
	npx tauri ios build
	@echo "=== 构建完成 ==="

# === 一键构建+部署到真机 (★ devicectl 原生, 推荐) ===
# 构建: tauri ios build (正确触发所有构建脚本)
# 部署: devicectl (CoreDevice 原生, 无需 lockdown 配对)
# 前置条件: iPhone 需在 Xcode 中配对过一次 (一次性, 之后无需 Xcode)
ios-device-deploy:
	@echo "========================================"
	@echo "  iOS 真机部署 (tauri build + devicectl)"
	@echo "========================================"
	@# 1. 检测设备 (优先已配对的, iPhone 优先于 iPad)
	@DEV_LINE=$$(xcrun devicectl list devices 2>/dev/null | grep -iE 'iphone|ipad' | grep -v 'unavailable' | sort -r -t'(' -k2 | head -1); \
	if [ -z "$$DEV_LINE" ]; then \
		echo "❌ 未检测到可用的 iOS 设备"; \
		echo "   请: 1) 解锁设备  2) 插 USB  3) 信任此电脑"; \
		exit 1; \
	fi; \
	DEV_ID=$$(echo "$$DEV_LINE" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1); \
	IS_IPHONE=$$(echo "$$DEV_LINE" | grep -qi 'iphone' && echo '📱' || echo '📟'); \
	IS_PAIRED=$$(echo "$$DEV_LINE" | grep -q "(paired)" && echo "yes" || echo "no"); \
	echo "$$IS_IPHONE 目标设备: $$DEV_ID"; \
	echo "🔐 配对状态: $$([ \"$$IS_PAIRED\" = \"yes\" ] && echo '✅ 已配对' || echo '❌ 未配对 (需一次性配对)')"; \
	if [ "$$IS_AVAIL" = "no" ]; then \
		echo "⚠️  设备当前不可用 (可能已锁屏), 请解锁 iPhone 后重试"; \
		exit 1; \
	fi; \
	if [ "$$IS_PAIRED" = "no" ]; then \
		echo ""; \
		echo "⚠️  首次需要配对! 只需做一次:"; \
		echo "   1. 打开 Xcode → Window → Devices and Simulators"; \
		echo "   2. 解锁 iPhone, 插 USB, Xcode 会自动完成配对"; \
		echo "   3. 以后就可以永久使用 make ios-device-deploy 了"; \
		echo ""; \
		echo "   或者运行 make ios-pair 查看详细步骤"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "🔨 Step 1/2: Tauri iOS 构建 (Debug)..."; \
	npx tauri ios build --debug 2>&1 | tail -5; \
	BUILD_EXIT=$$?; \
	if [ $$BUILD_EXIT -ne 0 ]; then \
		echo "❌ 构建失败 (退出码: $$BUILD_EXIT)"; \
		exit 1; \
	fi; \
	echo "✅ 构建成功"; \
	echo ""; \
	echo "🚀 Step 2/2: devicectl 安装到设备..."; \
	IPA_PATH="$$(find $(PROJ_ROOT)/src-tauri/gen/apple/build -name '*.ipa' -maxdepth 3 | head -1)"; \
	if [ -z "$$IPA_PATH" ]; then \
		echo "❌ 找不到 IPA, 请确认构建成功"; \
		exit 1; \
	fi; \
	echo "   IPA: $$IPA_PATH"; \
	xcrun devicectl device install app --device "$$DEV_ID" "$$IPA_PATH"; \
	echo ""; \
	echo "========================================"; \
	echo "  ✅ 部署完成！App 已在设备上"
	@echo "========================================"

ios-device-deploy-release:
	@echo "========================================"
	@echo "  iOS 真机部署 Release (tauri build + devicectl)"
	@echo "========================================"
	@DEV_LINE=$$(xcrun devicectl list devices 2>/dev/null | grep -iE 'iphone|ipad' | grep -v 'unavailable' | sort -r -t'(' -k2 | head -1); \
	if [ -z "$$DEV_LINE" ]; then \
		echo "❌ 未检测到可用的 iOS 设备"; \
		exit 1; \
	fi; \
	DEV_ID=$$(echo "$$DEV_LINE" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1); \
	IS_PAIRED=$$(echo "$$DEV_LINE" | grep -q "(paired)" && echo "yes" || echo "no"); \
	echo "📱 目标设备: $$DEV_ID ($$([ "$$IS_PAIRED" = "yes" ] && echo '已配对' || echo '未配对'))"; \
	if [ "$$IS_PAIRED" = "no" ]; then \
	if [ "$$IS_PAIRED" = "no" ]; then \
		echo "❌ 设备未配对, 请先运行 make ios-pair 完成一次性配对"; \
		exit 1; \
	fi; \
	echo "📱 目标设备: $$DEV_NAME (已配对)"; \
	echo ""; \
	echo "🔨 Step 1/2: Tauri iOS 构建 (Release)..."; \
	npx tauri ios build 2>&1 | tail -5; \
	BUILD_EXIT=$$?; \
	if [ $$BUILD_EXIT -ne 0 ]; then \
		echo "❌ 构建失败"; \
		exit 1; \
	fi; \
	echo "✅ 构建成功"; \
	echo ""; \
	echo "🚀 Step 2/2: devicectl 安装到设备..."; \
	IPA_PATH="$$(find $(PROJ_ROOT)/src-tauri/gen/apple/build -name '*.ipa' -maxdepth 3 | head -1)"; \
	if [ -z "$$IPA_PATH" ]; then \
		echo "❌ 找不到 IPA, 请确认构建成功"; \
		exit 1; \
	fi; \
	xcrun devicectl device install app --device "$$DEV_ID" "$$IPA_PATH"; \
	echo ""; \
	echo "========================================"; \
	echo "  ✅ 部署完成！"
	@echo "========================================"

# === 备用: ios-deploy 部署 (传统 lockdown 方式, 需先配对) ===
ios-deploy-legacy:
	@echo "========================================"
	@echo "  iOS 真机部署 (xcodebuild + ios-deploy)"
	@echo "  ⚠️  备用方案, 需要 lockdown 配对"
	@echo "========================================"
	@if [ -z "$$(ios-deploy --detect 2>/dev/null)" ]; then \
		echo "❌ ios-deploy 未检测到设备"; \
		echo "   请先打开 Xcode 完成设备配对, 或使用 make ios-device-deploy"; \
		exit 1; \
	fi
	@echo "🔨 Step 1/2: xcodebuild 构建..."
	cd src-tauri/gen/apple && xcodebuild \
		-project calculator-tauri.xcodeproj \
		-scheme $(IOS_SCHEME) \
		-configuration debug \
		-destination '$(IOS_DST)' \
		-derivedDataPath build \
		build 2>&1 | grep -E '(^\*\*|error:|warning:|BUILD)'
	@echo "✅ 构建成功"
	@echo "🚀 Step 2/2: ios-deploy 推送..."
	APP_PATH="$$(find $(PROJ_ROOT)/src-tauri/gen/apple/build/Build/Products/debug-iphoneos -name '*.app' -maxdepth 1 | head -1)"; \
	if [ -z "$$APP_PATH" ]; then \
		echo "❌ 找不到 .app 产物"; \
		exit 1; \
	fi; \
	ios-deploy --bundle "$$APP_PATH" --justlaunch
	@echo "✅ 部署完成"

# === 安装指定 IPA 到真机 ===
ios-ipa-install:
	@if [ -z "$(IPA)" ]; then \
		echo "用法: make ios-ipa-install IPA=/path/to/app.ipa"; \
		exit 1; \
	fi
	@DEV_LINE=$$(xcrun devicectl list devices 2>/dev/null | grep -iE 'iphone|ipad' | grep -v 'unavailable' | head -1); \
	if [ -z "$$DEV_LINE" ]; then \
		echo "❌ 未检测到可用的 iOS 设备"; \
		exit 1; \
	fi; \
	DEV_ID=$$(echo "$$DEV_LINE" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1); \
	echo "📦 安装 $(IPA) → $$DEV_ID..."; \
	xcrun devicectl device install app --device "$$DEV_ID" "$(IPA)"

# 一键发布：先检查再构建各平台
release: check
	@echo "=== 构建桌面 Release ==="
	npm run tauri build
	@echo "=== 构建 Android Release ==="
	npm run tauri android build
	@echo "=== 构建 iOS Release ==="
	npm run tauri ios build
	@echo "=== 发布完成 ==="

# ==================== 清理 ====================

clean: clean-rust clean-frontend clean-android clean-ios
	@echo "=== 构建产物已全部清理 ==="

clean-rust:
	@echo "=== 清理 Rust target/ ==="
	cd src-tauri && cargo clean

clean-frontend:
	@echo "=== 清理前端 ==="
	rm -rf dist/ dist-ssr/ .vite/ tsconfig.tsbuildinfo tsconfig.node.tsbuildinfo
	@echo "=== 前端清理完成 ==="

clean-android:
	@echo "=== 清理 Android 构建产物 ==="
	rm -rf src-tauri/gen/android/app/build/
	rm -rf src-tauri/gen/android/buildSrc/build/
	rm -rf src-tauri/gen/android/build/
	rm -rf src-tauri/gen/android/.gradle/
	rm -rf src-tauri/gen/android/.cxx/
	rm -rf src-tauri/gen/android/.tauri/

clean-ios:
	@echo "=== 清理 iOS 构建产物 ==="
	rm -rf src-tauri/gen/apple/build/
	rm -rf src-tauri/gen/apple/Externals/
	rm -rf src-tauri/gen/apple/calculator-tauri.xcodeproj/
	rm -rf src-tauri/gen/apple/calculator-tauri_iOS.xcworkspace/
	@echo "=== iOS 构建产物已清理 ==="

clean-all: clean
	@echo "=== 清理 node_modules/ ==="
	rm -rf node_modules/
	@echo "=== 深度清理完成，运行 npm install 恢复依赖 ==="
