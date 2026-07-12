#!/bin/sh
set -eu

# 动态获取 Windows 用户名
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')

# ==============================================
# 配置区：只需要修改这里！
# 格式：每行一个同步项
# Windows源路径|WSL目标路径[|文件权限|目录权限]
# 文件权限默认为 644，目录权限默认为 755。
# 单文件只使用“文件权限”；目录同步会同时使用文件和目录权限。
# ==============================================
SYNC_ITEMS="
/mnt/c/Users/${WIN_USER}/.claude/settings.json|$HOME/.claude/settings.json
/mnt/c/Users/${WIN_USER}/.codex/auth.json|$HOME/.codex/auth.json
/mnt/c/Users/${WIN_USER}/.agents/skills|$HOME/.claude/skills
/mnt/c/Users/${WIN_USER}/.agents/skills|$HOME/.agents/skills
/mnt/c/Users/${WIN_USER}/.ssh/id_ed25519|$HOME/.ssh/id_ed25519|600
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
    file_mode="$3"
    dir_mode="$4"

    # 检查源是否存在
    if [ ! -e "$source" ]; then
        return 0
    fi

    # 创建目标父目录
    mkdir -p "$(dirname "$target")"

    if [ -f "$source" ]; then
        # 同步单个文件
        cp -u "$source" "$target"
        chmod "$file_mode" "$target"

    elif [ -d "$source" ]; then
        # 同步目录
        if [ ! -d "$target" ] || [ "$source" -nt "$target" ]; then
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
        fi

        # 即使内容未变化，也应用配置的权限
        find "$target" -type d -exec chmod "$dir_mode" {} \;
        find "$target" -type f -exec chmod "$file_mode" {} \;
    fi
}

# 遍历所有同步项（POSIX兼容方式）
echo "$SYNC_ITEMS" | grep -v '^$' | while read -r item; do
    # 解析结构化配置
    old_ifs=$IFS
    IFS='|'
    read -r source target file_mode dir_mode <<EOF
$item
EOF
    IFS=$old_ifs

    # 使用默认权限，也允许每个同步项单独覆盖
    file_mode=${file_mode:-644}
    dir_mode=${dir_mode:-755}

    # 执行同步
    sync_item "$source" "$target" "$file_mode" "$dir_mode"
done
