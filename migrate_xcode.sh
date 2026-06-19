#!/bin/bash
set -e

# ============================================================
#  安全迁移脚本: 将 ~/Library/Developer → /Volumes/ExtraSSD/
#  
#  不影响系统启动，仅移动 Xcode 相关数据
#  执行前请关闭 Xcode!
# ============================================================

SRC="$HOME/Library/Developer"
DST="/Volumes/ExtraSSD/Library/Developer"

echo "========================================"
echo "  系统盘空间迁移脚本"
echo "========================================"
echo ""

# 1. 检查 Xcode 是否关闭
if pgrep -x Xcode > /dev/null 2>&1; then
    echo "❌ 请先关闭 Xcode 再运行此脚本!"
    exit 1
fi
echo "✅ Xcode 未运行"

# 2. 检查源目录
if [ ! -d "$SRC" ]; then
    echo "❌ 源目录不存在: $SRC"
    exit 1
fi

# 3. 检查是否已经是符号链接
if [ -L "$SRC" ]; then
    echo "⚠️  $SRC 已经是符号链接，无需迁移"
    ls -la "$SRC"
    exit 0
fi

# 4. 显示迁移前空间
echo ""
echo "📊 迁移前系统盘:"
df -h / | tail -1

# 5. 创建目标目录
mkdir -p "$(dirname "$DST")"

# 6. 复制 (保留所有属性和符号链接)
echo ""
echo "📦 正在复制 $SRC → $DST ..."
echo "   (约 3GB, 请耐心等待)"
cp -a "$SRC" "$DST"
echo "✅ 复制完成"

# 7. 验证
SRC_SIZE=$(du -sk "$SRC" 2>/dev/null | cut -f1)
DST_SIZE=$(du -sk "$DST" 2>/dev/null | cut -f1)
echo "   源: ${SRC_SIZE}K  目标: ${DST_SIZE}K"

if [ "$SRC_SIZE" != "$DST_SIZE" ]; then
    echo "⚠️  大小不一致，请手动检查"
    echo "   源: $SRC"
    echo "   目标: $DST"
    exit 1
fi

# 8. 删除源目录并创建符号链接
echo ""
echo "🔗 创建符号链接..."
rm -rf "$SRC"
ln -s "$DST" "$SRC"
echo "✅ 符号链接已创建: $SRC → $DST"

# 9. 最终验证
echo ""
echo "📊 迁移后系统盘:"
df -h / | tail -1
echo ""
echo "========================================"
echo "  ✅ 迁移完成!"
echo "  $SRC → $DST"
echo "========================================"
