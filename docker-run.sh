#!/usr/bin/env bash
# ==============================================================================
# docker-run.sh - 用容器编译 GKI 内核，本机不用装任何编译依赖
#
#   ./docker-run.sh -v android14-6.1-138
#   ./docker-run.sh                     # 进交互式向导
#   ./docker-run.sh --list              # 看支持哪些版本
#
# 产物落在当前目录的 gki-out/ 下。
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
log()  { printf '%s[docker]%s %s\n' "$C_CYAN"  "$C_OFF" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n'   "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '%s[WARN]%s %s\n'   "$C_YELLOW" "$C_OFF" "$*"; }
die()  { printf '%s[FAIL]%s %s\n'   "$C_RED"    "$C_OFF" "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 \
    || die "没装 Docker：https://www.docker.com/products/docker-desktop"

if ! docker info >/dev/null 2>&1; then
    warn "Docker 好像没启动，等一下它会自己拉起"
    open -a Docker 2>/dev/null || true
    for _ in $(seq 1 30); do
        docker info >/dev/null 2>&1 && break
        sleep 2
    done
    docker info >/dev/null 2>&1 || die "Docker 起不来，手动打开 Docker Desktop 再重试"
fi

MEM_GB=$(docker info --format '{{.MemTotal}}' 2>/dev/null | awk '{printf "%d", $1/1024/1024/1024}')
if [[ -n "$MEM_GB" && "$MEM_GB" -lt 8 ]]; then
    warn "Docker 可用内存只有 ${MEM_GB}GB，编译大概率失败"
    warn "请在 Docker Desktop → Settings → Resources 里把内存调到 8GB 以上"
    read -r -p "   仍然继续？[y/N] " go
    [[ "$go" == "y" || "$go" == "Y" ]] || exit 1
fi

mkdir -p "$SCRIPT_DIR/gki-out"

log "构建镜像（首次约 2-5 分钟，之后走缓存秒起）"
docker build -t gki-builder "$SCRIPT_DIR" || die "镜像构建失败"

ok "镜像就绪，开始编译"
exec docker run --rm -it \
    -v "$SCRIPT_DIR/gki-out:/work/gki-out" \
    gki-builder "$@"
