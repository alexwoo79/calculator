#!/bin/bash
set -e

# ============================================================
#  迁移应用数据到外置 SSD
#  
#  仅迁移明确安全的应用数据，不碰 Containers
# ============================================================

DST_BASE="/Volumes/ExtraSSD/Library/Application Support"
APPS=(
    "Google"
    "obsidian"
    "RStudio"
    "Postman"
)

echo "========================================"
echo "  应用数据迁移 → 外置 SSD"
echo "========================================"
echo ""

SRC_BASE="$HOME/Library/Application Support"

for app in "${APPS[@]}"; do
    SRC="$SRC_BASE/$app"
    DST="$DST_BASE/$app"
    
    if [ ! -d "$SRC" ]; then
        echo "⏭️  跳过 $app (不存在)"
        echo ""
        continue
    fi
    
    if [ -L "$SRC" ]; then
        echo "⏭️  跳过 $app (已是符号链接)"
        echo ""
        continue
    fi
    
    echo "📦 迁移 $app ..."
    du -sh "$SRC" 2>/dev/null
    
    mkdir -p "$DST_BASE"
    cp -a "$SRC" "$DST"
    rm -rf "$SRC"
    ln -s "$DST" "$SRC"
    echo "   ✅ $SRC → $DST"
    echo ""
done

echo "📊 迁移后系统盘:"
df -h / | tail -1
echo ""
echo "========================================"
echo "  ✅ 应用数据迁移完成"
echo "========================================"
