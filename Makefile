# ============================================================
#  Any Calculator — Tauri (Vue + Vite + Rust)  Makefile
# ============================================================

.PHONY: help dev build build-debug build-android release clean clean-rust clean-frontend clean-android clean-all

# 默认目标
help:
	@echo "Any Calculator — 可用目标:"
	@echo ""
	@echo "  开发调试:"
	@echo "    make dev              启动桌面开发模式 (热更新)"
	@echo "    make dev-android      启动 Android 开发模式"
	@echo ""
	@echo "  构建发布:"
	@echo "    make build            桌面 Release 构建 (macOS .dmg)"
	@echo "    make build-debug      桌面 Debug 构建"
	@echo "    make build-android    Android Release APK/AAB"
	@echo "    make release          一键发布 (桌面 + Android)"
	@echo ""
	@echo "  清理:"
	@echo "    make clean            清理所有构建产物"
	@echo "    make clean-rust       清理 Rust target/"
	@echo "    make clean-frontend   清理前端 dist/ node_modules/"
	@echo "    make clean-android    清理 Android 构建产物"
	@echo "    make clean-all        深度清理 (含 node_modules)"
	@echo ""

# ==================== 开发调试 ====================

dev:
	npm run tauri dev

dev-android:
	npm run tauri android dev

# ==================== 构建 ====================

# 桌面 Release 构建
build:
	npm run tauri build

# 桌面 Debug 构建
build-debug:
	npm run tauri build -- --debug

# Android Release 构建
build-android:
	npm run tauri android build

# 一键发布：先清理，再依次构建桌面和 Android
release: clean
	@echo "=== 构建桌面 Release ==="
	npm run tauri build
	@echo "=== 构建 Android Release ==="
	npm run tauri android build
	@echo "=== 发布完成 ==="

# ==================== 清理 ====================

# 清理所有构建产物
clean: clean-rust clean-frontend clean-android
	@echo "=== 构建产物已全部清理 ==="

# 清理 Rust 编译产物 (src-tauri/target/)
clean-rust:
	@echo "=== 清理 Rust target/ ==="
	cd src-tauri && cargo clean

# 清理前端构建产物
clean-frontend:
	@echo "=== 清理前端 dist/ ==="
	rm -rf dist/
	rm -rf dist-ssr/
	rm -rf .vite/

# 清理 Android 构建产物
clean-android:
	@echo "=== 清理 Android 构建产物 ==="
	rm -rf src-tauri/gen/android/app/build/
	rm -rf src-tauri/gen/android/buildSrc/build/
	rm -rf src-tauri/gen/android/build/
	rm -rf src-tauri/gen/android/.gradle/
	rm -rf src-tauri/gen/android/.cxx/
	rm -rf src-tauri/gen/android/.tauri/

# 深度清理 (含 node_modules)
clean-all: clean
	@echo "=== 清理 node_modules/ ==="
	rm -rf node_modules/
	@echo "=== 深度清理完成，运行 npm install 恢复依赖 ==="
