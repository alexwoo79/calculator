# ============================================================
#  Any Calculator — Tauri (Vue + Vite + Rust)  Makefile
# ============================================================

.PHONY: help typecheck check dev dev-android dev-ios build build-debug build-android build-android-debug build-ios run-ios ios-rust ios-xcode release clean clean-rust clean-frontend clean-android clean-ios clean-all

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
	@echo "    make run-ios          直连 iPhone 真机安装运行"
	@echo "    make release          一键发布 (check → 桌面 + Android + iOS)"
	@echo ""
	@echo "  iOS 专用:"
	@echo "    make ios-rust         仅编译 Rust → iOS (aarch64-apple-ios)"
	@echo "    make ios-xcode        在 Xcode 中打开 iOS 项目"
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

# iOS 直连真机部署
# Apple Silicon Mac 上 xcodebuild 命令行始终选 "My Mac" 而非真 iPhone，
# 需要通过 Xcode GUI 选择设备后 Cmd+R 部署。
IOS_DEVICE := $(shell xcrun xctrace list devices 2>&1 | grep -i 'iPhone' | grep -v 'Simulator' | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}')

run-ios:
	@echo "=== 检测到 iPhone: $(IOS_DEVICE) ==="
	@echo "打开 Xcode → Product → Destination → 选"吴利利的iPhone" → Cmd+R"
	open -a Xcode src-tauri/gen/apple/calculator-tauri.xcodeproj

# 仅编译 Rust → iOS arm64（调试用）
ios-rust:
	@echo "=== 编译 Rust for iOS (aarch64-apple-ios) ==="
	cd src-tauri && cargo build --target aarch64-apple-ios
	@echo "=== Rust iOS 编译完成 ==="

# 在 Xcode 中打开 iOS 项目（手动调试/Archive）
ios-xcode:
	@echo "=== 打开 Xcode iOS 项目 ==="
	open -a Xcode src-tauri/gen/apple/calculator-tauri.xcodeproj

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
	@echo "=== 清理前端 ===\n\trm -rf dist/ dist-ssr/ .vite/ tsconfig.tsbuildinfo tsconfig.node.tsbuildinfo\n\t@echo \"=== 前端清理完成 ==="

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
