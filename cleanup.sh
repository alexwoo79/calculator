#!/bin/bash
#
# macOS 系统清理脚本 — 清理垃圾、缓存、日志等
# 用法: bash cleanup.sh [--aggressive]
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

AGGRESSIVE=false
if [[ "${1:-}" == "--aggressive" ]]; then
  AGGRESSIVE=true
fi

# ---------- 辅助函数 ----------
format_size() {
  local bytes=$1
  if command -v numfmt &>/dev/null; then
    numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B"
  else
    if (( bytes > 1073741824 )); then
      echo "$((bytes / 1073741824))GB"
    elif (( bytes > 1048576 )); then
      echo "$((bytes / 1048576))MB"
    elif (( bytes > 1024 )); then
      echo "$((bytes / 1024))KB"
    else
      echo "${bytes}B"
    fi
  fi
}

get_dir_size() {
  local dir="$1"
  if [ -d "$dir" ]; then
    du -sk "$dir" 2>/dev/null | cut -f1
  else
    echo 0
  fi
}

confirm() {
  local msg="$1"
  echo -e "${YELLOW}⚠  $msg${NC}"
  read -rp "   是否继续? [y/N] " yn
  case "$yn" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# 全局变量追踪清理总量
CLEANED_TOTAL=0

clean_dir() {
  local dir="$1"
  local desc="$2"
  local pattern="${3:-*}"

  if [ ! -d "$dir" ]; then
    echo -e "  ${CYAN}→${NC} $desc: 目录不存在,跳过"
    return
  fi

  local before
  before=$(get_dir_size "$dir")
  if [ "$before" -eq 0 ]; then
    echo -e "  ${CYAN}→${NC} $desc: 已为空,跳过"
    return
  fi

  echo -e "  ${YELLOW}清理${NC} $desc ... ($(format_size $((before * 1024))))"

  if [ "$pattern" = "*" ]; then
    find "$dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | while IFS= read -r -d '' f; do
      rm -rf "$f" 2>/dev/null || true
    done
  else
    find "$dir" -name "$pattern" -print0 2>/dev/null | while IFS= read -r -d '' f; do
      rm -rf "$f" 2>/dev/null || true
    done
  fi

  local after
  after=$(get_dir_size "$dir")
  local freed=$((before - after))
  CLEANED_TOTAL=$((CLEANED_TOTAL + freed))
  echo -e "    ${GREEN}✓ 释放 $(format_size $((freed * 1024)))${NC}"
}

# ---------- 打印磁盘空间 ----------
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN}     macOS 系统清理工具${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo ""

df -h / | tail -1 | awk '{print "磁盘总空间: " $2 "  已用: " $3 " (" $5 ")  可用: " $4}'
echo ""

# ===================== 安全清理区 =====================
echo -e "${GREEN}━━━ 第一步: 安全清理 (无需 sudo) ━━━${NC}"
echo ""

# 1. 用户缓存
echo -e "${YELLOW}[1/10] 用户缓存${NC}"
clean_dir "$HOME/Library/Caches" "用户缓存目录"

# 2. 系统日志
echo ""
echo -e "${YELLOW}[2/10] 日志文件${NC}"
clean_dir "$HOME/Library/Logs" "用户日志"

# 3. 临时文件
echo ""
echo -e "${YELLOW}[3/10] 临时文件${NC}"
clean_dir "$TMPDIR" "系统临时文件"

# 4. Safari 缓存
echo ""
echo -e "${YELLOW}[4/10] 浏览器缓存${NC}"
clean_dir "$HOME/Library/Safari/LocalStorage" "Safari 本地存储"
clean_dir "$HOME/Library/Containers/com.apple.Safari/Data/Library/Caches" "Safari 缓存"

# 5. Chrome/Edge 缓存
echo ""
echo -e "${YELLOW}[5/10] Chrome/Edge 缓存${NC}"
clean_dir "$HOME/Library/Caches/Google/Chrome" "Chrome 缓存"
clean_dir "$HOME/Library/Caches/com.google.Chrome" "Chrome 缓存 (备用)"
clean_dir "$HOME/Library/Caches/com.microsoft.edgemac" "Edge 缓存"

# 6. Xcode 派生数据 & 模拟器
echo ""
echo -e "${YELLOW}[6/10] Xcode 派生数据 & 模拟器${NC}"
clean_dir "$HOME/Library/Developer/Xcode/DerivedData" "Xcode DerivedData"
clean_dir "$HOME/Library/Developer/Xcode/Archives" "Xcode Archives"
clean_dir "$HOME/Library/Developer/Xcode/iOS DeviceSupport" "旧 iOS DeviceSupport"

if [ -d "$HOME/Library/Developer/CoreSimulator" ]; then
  if command -v xcrun &>/dev/null; then
    echo -e "  ${YELLOW}清理${NC} 不可用模拟器 ..."
    xcrun simctl delete unavailable 2>/dev/null && \
      echo -e "    ${GREEN}✓ 完成${NC}" || \
      echo -e "    ${CYAN}→ 无可清理的模拟器${NC}"
  fi
fi

# 7. Homebrew 缓存
echo ""
echo -e "${YELLOW}[7/10] Homebrew 缓存${NC}"
if command -v brew &>/dev/null; then
  BREW_CACHE=$(brew --cache 2>/dev/null || echo "")
  if [ -n "$BREW_CACHE" ] && [ -d "$BREW_CACHE" ]; then
    clean_dir "$BREW_CACHE" "Homebrew 下载缓存"
  fi
  echo -e "  ${YELLOW}清理${NC} 旧版本 formulae ..."
  brew cleanup --prune=all 2>/dev/null && \
    echo -e "    ${GREEN}✓ 完成${NC}" || \
    echo -e "    ${CYAN}→ brew cleanup 跳过${NC}"
else
  echo -e "  ${CYAN}→ Homebrew 未安装, 跳过${NC}"
fi

# 8. Node.js 生态缓存
echo ""
echo -e "${YELLOW}[8/10] Node.js 生态缓存${NC}"
clean_dir "$HOME/.npm/_cacache" "npm 缓存"
if command -v yarn &>/dev/null; then
  echo -e "  ${YELLOW}清理${NC} Yarn 缓存 ..."
  yarn cache clean --all 2>/dev/null && \
    echo -e "    ${GREEN}✓ Yarn 缓存清理完成${NC}" || \
    echo -e "    ${CYAN}→ Yarn 跳过${NC}"
fi
clean_dir "$HOME/Library/Caches/pnpm" "pnpm 缓存"

# 9. Ruby gem 缓存
echo ""
echo -e "${YELLOW}[9/10] Ruby gem 缓存${NC}"
if command -v gem &>/dev/null; then
  echo -e "  ${YELLOW}清理${NC} 旧版 gem ..."
  gem cleanup 2>/dev/null && echo -e "    ${GREEN}✓ 完成${NC}" || echo -e "    ${CYAN}→ gem cleanup 跳过${NC}"
fi

# 10. 编辑器缓存
echo ""
echo -e "${YELLOW}[10/10] 编辑器缓存${NC}"
clean_dir "$HOME/Library/Caches/com.microsoft.VSCode" "VS Code 缓存"
clean_dir "$HOME/Library/Caches/com.microsoft.VSCodeInsiders" "VS Code Insiders 缓存"
clean_dir "$HOME/Library/Application Support/Code/Cache" "VS Code 缓存 (备用)"
clean_dir "$HOME/Library/Application Support/Code/CachedData" "VS Code CachedData"
clean_dir "$HOME/Library/Application Support/Code/User/workspaceStorage" "VS Code 工作区存储"

# ===================== 激进清理区 =====================
if $AGGRESSIVE; then
  echo ""
  echo -e "${RED}━━━ 第二步: 激进清理 (需确认) ━━━${NC}"
  echo ""

  # A. 清空废纸篓
  if confirm "清空废纸篓?"; then
    echo -e "  ${YELLOW}清空废纸篓...${NC}"
    osascript -e 'tell application "Finder" to empty trash' 2>/dev/null && \
      echo -e "    ${GREEN}✓ 废纸篓已清空${NC}" || \
      echo -e "    ${RED}✗ 清空失败${NC}"
  fi

  echo ""

  # B. 下载文件夹中 30 天前的安装包
  if confirm "删除 Downloads 中 30 天前的安装包 (.dmg/.pkg/.zip/.tar.gz/.iso)?"; then
    echo -e "  ${YELLOW}扫描中...${NC}"
    count=0
    while IFS= read -r -d '' f; do
      echo -e "    删除: $(basename "$f")"
      rm -f "$f"
      ((count++)) || true
    done < <(find "$HOME/Downloads" -maxdepth 1 \( -name "*.dmg" -o -name "*.pkg" -o -name "*.zip" -o -name "*.tar.gz" -o -name "*.iso" \) -mtime +30 -print0 2>/dev/null)
    echo -e "    ${GREEN}✓ 删除 $count 个文件${NC}"
  fi

  echo ""

  # C. Docker 缓存
  if command -v docker &>/dev/null; then
    if confirm "清理 Docker 构建缓存和无用镜像?"; then
      echo -e "  ${YELLOW}Docker 清理中...${NC}"
      docker system prune -af --volumes 2>/dev/null && \
        echo -e "    ${GREEN}✓ Docker 清理完成${NC}" || \
        echo -e "    ${CYAN}→ Docker 未运行或无权限${NC}"
    fi
  fi

  echo ""

  # D. 系统级缓存 (需 sudo)
  if confirm "清理系统级缓存 (需要 sudo 密码)?"; then
    echo -e "  ${YELLOW}清理 /Library/Caches ...${NC}"
    sudo find /Library/Caches -mindepth 1 -maxdepth 1 -print0 2>/dev/null | while IFS= read -r -d '' f; do
      sudo rm -rf "$f" 2>/dev/null || true
    done
    echo -e "    ${GREEN}✓ 系统缓存已清理${NC}"

    echo -e "  ${YELLOW}清理 /var/log 旧日志 ...${NC}"
    sudo find /var/log -name "*.log" -mtime +7 -print0 2>/dev/null | while IFS= read -r -d '' f; do
      sudo rm -f "$f" 2>/dev/null || true
    done
    echo -e "    ${GREEN}✓ 旧系统日志已清理${NC}"
  fi

  echo ""

  # E. Time Machine 本地快照
  if confirm "删除本地 Time Machine 快照 (不影响外置备份)?"; then
    echo -e "  ${YELLOW}列出本地快照...${NC}"
    tmutil listlocalsnapshots / 2>/dev/null | while read -r snap; do
      if [[ "$snap" == com.apple.TimeMachine.* ]]; then
        echo -e "    删除: $snap"
        sudo tmutil deletelocalsnapshots "${snap##*.}" 2>/dev/null || true
      fi
    done
    echo -e "    ${GREEN}✓ 本地快照已清理${NC}"
  fi
else
  echo ""
  echo -e "${CYAN}提示: 使用 --aggressive 参数可执行深度清理${NC}"
  echo -e "${CYAN}  bash cleanup.sh --aggressive${NC}"
fi

# ===================== 汇总 =====================
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  清理完成! 本次释放约 $(format_size $((CLEANED_TOTAL * 1024)))${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo ""
df -h / | tail -1 | awk '{print "当前: 总空间 " $2 "  已用 " $3 " (" $5 ")  可用 " $4}'
echo ""
