#!/bin/sh
set -eu

# ==============================================
# 配置区：只需要修改这里！
# 格式：每行一个同步项 "Windows源路径:WSL目标路径"
# ==============================================
SYNC_ITEMS="
/mnt/c/Users/32757/.claude/settings.json:$HOME/.claude/settings.json
/mnt/c/Users/32757/.claude/skills:$HOME/.claude/skills
"

# 标志文件（防止重复执行）
FLAG_FILE="/tmp/wsl_sync_files.running"
START_TIME_MS=$(date +%s%3N)

# ==============================================
# 核心逻辑（无需修改）
# ==============================================
# 清理函数
cleanup() {
    rm -f "$FLAG_FILE"
    end_time_ms=$(date +%s%3N)
    # echo "sync_files.sh completed in $((end_time_ms - START_TIME_MS))ms"
}
trap cleanup EXIT INT TERM

# 防止并发执行
if [ -f "$FLAG_FILE" ]; then
    exit 0
fi
touch "$FLAG_FILE"

# 通用同步函数
sync_item() {
    source="$1"
    target="$2"

    # 检查源是否存在
    if [ ! -e "$source" ]; then
        return 0
    fi

    # 创建目标父目录
    mkdir -p "$(dirname "$target")"

    if [ -f "$source" ]; then
        # 同步单个文件
        cp -u "$source" "$target"
        chmod 644 "$target"

    elif [ -d "$source" ]; then
        # 同步目录
        if [ -d "$target" ] && [ ! "$source" -nt "$target" ]; then
            return 0
        fi

        mkdir -p "$target"
        cp -rup "$source"/* "$target/" 2>/dev/null || true

        # 删除目标中源不存在的文件
        find "$target" -type f | while read -r target_file; do
            rel_path="${target_file#$target/}"
            if [ ! -f "$source/$rel_path" ]; then
                rm -f "$target_file"
            fi
        done

        # 删除空目录
        find "$target" -type d -empty -delete

        # 设置权限
        find "$target" -type d -exec chmod 755 {} \;
        find "$target" -type f -exec chmod 644 {} \;
    fi
}

# 遍历所有同步项（POSIX兼容方式）
echo "$SYNC_ITEMS" | grep -v '^$' | while read -r item; do
    # 分割源路径和目标路径（只分割第一个冒号）
    source=$(echo "$item" | cut -d: -f1)
    target=$(echo "$item" | cut -d: -f2-)
    
    # 展开变量（处理 $HOME 等环境变量）
    source=$(eval echo "$source")
    target=$(eval echo "$target")

    # 执行同步
    sync_item "$source" "$target"
done

