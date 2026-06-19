# ============================================================
#  Any Calculator — Tauri (Vue + Vite + Rust)  Makefile
# ============================================================

.PHONY: help typecheck check dev dev-android dev-ios build build-debug build-android build-android-debug build-ios run-ios ios-rust ios-xcode ios-doctor ios-device-build ios-device-build-release ios-device-deploy ios-device-deploy-release ios-ipa-install release clean clean-rust clean-frontend clean-android clean-ios clean-all

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
	@echo "    make ios-doctor       诊断 iOS 开发环境 (设备/证书/工具)"
	@echo "    make ios-device-build    xcodebuild 构建 .app (Debug, 不部署)"
	@echo "    make ios-device-build-release  xcodebuild 构建 .app (Release)"
	@echo "    make ios-device-deploy    ★ 一键构建+部署到真机 (推荐)"
	@echo "    make ios-device-deploy-release  构建 Release + 部署到真机"
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
# 解决 Xcode 连接设备频繁报错的问题：
#   核心思路 — xcodebuild 命令行构建 + ios-deploy 推送 = 完全绕过 Xcode GUI
#   先决条件 — brew install ios-deploy (已安装: 1.12.2)

IOS_PROJ    := src-tauri/gen/apple/calculator-tauri.xcodeproj
IOS_SCHEME  := calculator-tauri_iOS
IOS_DST     := generic/platform=iOS

# 获取当前 USB 连接的 iOS 设备 ID（优先真机）
IOS_DEVICE_ID := $(shell ios-deploy --detect 2>/dev/null || echo "")

# === 诊断 ===
ios-doctor:
	@echo "========== iOS 开发环境诊断 =========="
	@echo ""
	@echo "[1/5] 必要工具检查..."
	@command -v xcodebuild >/dev/null && echo "  ✅ xcodebuild: $$(xcodebuild -version | head -1)" || echo "  ❌ xcodebuild 未找到"
	@command -v ios-deploy >/dev/null   && echo "  ✅ ios-deploy: $$(ios-deploy --version)" || echo "  ❌ ios-deploy 未安装 → brew install ios-deploy"
	@command -v idevice_id >/dev/null   && echo "  ✅ idevice_id (libimobiledevice)" || echo "  ⚠️  idevice_id 未安装 → brew install libimobiledevice"
	@echo ""
	@echo "[2/5] USB 连接的真机设备..."
	@if [ -n "$(IOS_DEVICE_ID)" ]; then \
		echo "  ✅ 检测到设备: $(IOS_DEVICE_ID)"; \
		ios-deploy --list-bundle_id --detect 2>/dev/null || true; \
	else \
		echo "  ❌ 未检测到 USB 连接的 iOS 设备"; \
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

# === 仅构建 .app (不部署) ===
ios-device-build:
	@echo "=== xcodebuild 构建 iOS Debug (真机) ==="
	@if [ ! -d "$(IOS_PROJ)" ]; then \
		echo "❌ 项目不存在，请先运行: npx tauri ios init"; \
		exit 1; \
	fi
	cd src-tauri/gen/apple && xcodebuild \
		-project calculator-tauri.xcodeproj \
		-scheme $(IOS_SCHEME) \
		-configuration debug \
		-destination '$(IOS_DST)' \
		-derivedDataPath build \
		build 2>&1 | grep -E '(^\*\*|error:|warning:|BUILD)'
	@echo "=== 构建完成，.app 位于: src-tauri/gen/apple/build/Build/Products/debug-iphoneos/ ==="

ios-device-build-release:
	@echo "=== xcodebuild 构建 iOS Release (真机) ==="
	@if [ ! -d "$(IOS_PROJ)" ]; then \
		echo "❌ 项目不存在，请先运行: npx tauri ios init"; \
		exit 1; \
	fi
	cd src-tauri/gen/apple && xcodebuild \
		-project calculator-tauri.xcodeproj \
		-scheme $(IOS_SCHEME) \
		-configuration release \
		-destination '$(IOS_DST)' \
		-derivedDataPath build \
		build 2>&1 | grep -E '(^\*\*|error:|warning:|BUILD)'
	@echo "=== 构建完成 ==="

# === 一键构建+部署到真机 (★ 推荐日常使用) ===
ios-device-deploy:
	@echo "========================================"
	@echo "  iOS 真机部署 (xcodebuild + ios-deploy)"
	@echo "========================================"
	@# 检查设备
	@if [ -z "$(IOS_DEVICE_ID)" ]; then \
		echo "❌ 未检测到 USB 连接的 iOS 设备"; \
		echo "   请确保: 1) USB 已连接  2) 设备已解锁  3) 已信任此电脑"; \
		exit 1; \
	fi
	@echo "📱 目标设备: $(IOS_DEVICE_ID)"
	@echo ""
	@# 构建
	@echo "🔨 Step 1/2: xcodebuild 构建 (Debug)..."
	cd src-tauri/gen/apple && xcodebuild \
		-project calculator-tauri.xcodeproj \
		-scheme $(IOS_SCHEME) \
		-configuration debug \
		-destination '$(IOS_DST)' \
		-derivedDataPath build \
		build 2>&1 | grep -E '(^\*\*|error:|warning:|BUILD)'
	@echo "✅ 构建成功"
	@echo ""
	@# 部署
	@echo "🚀 Step 2/2: ios-deploy 推送到设备..."
	APP_PATH="$$(find src-tauri/gen/apple/build/Build/Products/debug-iphoneos -name '*.app' -maxdepth 1 | head -1)"; \
	if [ -z "$$APP_PATH" ]; then \
		echo "❌ 找不到 .app 产物"; \
		exit 1; \
	fi; \
	echo "   App: $$APP_PATH"; \
	ios-deploy --bundle "$$APP_PATH" --justlaunch
	@echo ""
	@echo "========================================"
	@echo "  ✅ 部署完成！App 已在设备上启动"
	@echo "========================================"

ios-device-deploy-release:
	@echo "========================================"
	@echo "  iOS 真机部署 Release (xcodebuild + ios-deploy)"
	@echo "========================================"
	@if [ -z "$(IOS_DEVICE_ID)" ]; then \
		echo "❌ 未检测到 USB 连接的 iOS 设备"; \
		exit 1; \
	fi
	@echo "📱 目标设备: $(IOS_DEVICE_ID)"
	@echo ""
	@echo "🔨 Step 1/2: xcodebuild 构建 (Release)..."
	cd src-tauri/gen/apple && xcodebuild \
		-project calculator-tauri.xcodeproj \
		-scheme $(IOS_SCHEME) \
		-configuration release \
		-destination '$(IOS_DST)' \
		-derivedDataPath build \
		build 2>&1 | grep -E '(^\*\*|error:|warning:|BUILD)'
	@echo "✅ 构建成功"
	@echo ""
	@echo "🚀 Step 2/2: ios-deploy 推送到设备..."
	APP_PATH="$$(find src-tauri/gen/apple/build/Build/Products/release-iphoneos -name '*.app' -maxdepth 1 | head -1)"; \
	if [ -z "$$APP_PATH" ]; then \
		echo "❌ 找不到 .app 产物"; \
		exit 1; \
	fi; \
	echo "   App: $$APP_PATH"; \
	ios-deploy --bundle "$$APP_PATH" --justlaunch
	@echo ""
	@echo "========================================"
	@echo "  ✅ 部署完成！"
	@echo "========================================"

# === 安装指定 IPA 到真机 ===
ios-ipa-install:
	@if [ -z "$(IPA)" ]; then \
		echo "用法: make ios-ipa-install IPA=/path/to/app.ipa"; \
		exit 1; \
	fi
	@if [ -z "$(IOS_DEVICE_ID)" ]; then \
		echo "❌ 未检测到 USB 连接的 iOS 设备"; \
		exit 1; \
	fi
	@echo "📦 安装 $(IPA) → $(IOS_DEVICE_ID)..."
	ios-deploy --bundle "$(IPA)" --justlaunch

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
