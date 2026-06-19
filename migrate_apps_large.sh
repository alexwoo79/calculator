#!/bin/bash
set -e

# ============================================================
#  迁移大型应用 → /Volumes/ExtraSSD/Applications/
#
#  安全说明:
#  - Docker / OneDrive 已排除 (有系统守护进程和扩展)
#  - 其他应用为自包含 .app 包，迁移后功能不受影响
#  - 如遇问题，删除符号链接，移回原处即可恢复
# ============================================================

DST_BASE="/Volumes/ExtraSSD/Applications"

# 按大小排序，最大的先迁
APPS=(
    "Microsoft Excel.app"
    "wpsoffice.app"
    "RStudio.app"
    "WeChat.app"
    "Positron.app"
    "Google Chrome.app"
    "Codex.app"
    "Visual Studio Code.app"
)

echo "========================================"
echo "  应用迁移 → 外置 SSD"
echo "========================================"
echo ""

# 检查目标
if [ ! -d "/Volumes/ExtraSSD" ]; then
    echo "❌ 外置 SSD 未挂载: /Volumes/ExtraSSD"
    exit 1
fi

echo "📊 迁移前系统盘:"
df -h / | tail -1
echo ""

mkdir -p "$DST_BASE"

MOVED=0

for app in "${APPS[@]}"; do
    SRC="/Applications/$app"
    DST="$DST_BASE/$app"
    
    if [ ! -d "$SRC" ]; then
        echo "⏭️  跳过: $app (不存在)"
        continue
    fi
    
    if [ -L "$SRC" ]; then
        echo "⏭️  跳过: $app (已是符号链接)"
        continue
    fi
    
    # 检查应用是否在运行
    APP_NAME="${app%.app}"
    if pgrep -qi "$APP_NAME" 2>/dev/null; then
        echo "⏭️  跳过: $app (正在运行, 请先退出)"
        continue
    fi
    
    SIZE=$(du -sh "$SRC" 2>/dev/null | cut -f1)
    echo ""
    echo "📦 $app ($SIZE)"
    echo "   复制中..."
    
    cp -a "$SRC" "$DST"
    
    SRC_SIZE=$(du -sk "$SRC" 2>/dev/null | cut -f1)
    DST_SIZE=$(du -sk "$DST" 2>/dev/null | cut -f1)
    
    if [ "$SRC_SIZE" = "$DST_SIZE" ]; then
        rm -rf "$SRC"
        ln -s "$DST" "$SRC"
        echo "   ✅ 已迁移: $SRC → $DST"
        MOVED=$((MOVED + 1))
    else
        echo "   ⚠️  大小不一致，跳过删除。请手动检查"
        rm -rf "$DST"
    fi
done

echo ""
echo "📊 迁移后系统盘:"
df -h / | tail -1
echo ""
echo "========================================"
echo "  ✅ 完成: 迁移了 $MOVED 个应用"
echo ""
echo "  ⚠️  未迁移(需手动处理):"
echo "     Docker.app         — 有系统守护进程"
echo "     OneDrive.app       — 有 Finder 扩展"
echo "========================================"
