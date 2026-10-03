#!/usr/bin/env bash
# ==============================================================================
# gkibuild.sh - Droidspaces GKI 内核一键编译
#
#   不带参数运行  -> 交互式向导：选版本 -> 选功能 -> 自动拉取源码 -> 编译出包
#   带参数运行    -> 命令行模式：./gkibuild.sh -v android14-6.1-138
#
# 本地模式需要 Linux / WSL；网络不好可选云端模式（走 GitHub Actions）
# ==============================================================================
set -euo pipefail

TOOL_REPO="404-GCross/Droidspaces_GKI_Buildin_Local"
SRC_REPO="404-GCross/GKI-Kernel-Source_Fetch"
SRC_TAG="${REPO_TAG:-all-full-kernel-sources-20260821-32436876080}"
UPSTREAM_MIRRORS=("https://gh-proxy.com/" "https://gh.llkk.cc/" "https://gh.ddlc.top/")

AV=""; KV=""; SUB=""; VERSION=""
MIRROR=""; KSU="ReSukiSU"; SLOT="678"; KSU_BRANCH="Stable(标准)"
CVE="true"; ZRAM="false"; KPM="false"; LTO="thin"
OUTDIR=""; MODE="local"; WAIT="false"; INSTALL_DEPS="true"
CACHE_DIR="${GKI_CACHE_DIR:-$HOME/.cache/gkibuild}"

C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
log()  { printf '%s[gkibuild]%s %s\n' "$C_CYAN" "$C_OFF" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n'   "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '%s[WARN]%s %s\n'   "$C_YELLOW" "$C_OFF" "$*"; }
die()  { printf '%s[FAIL]%s %s\n'   "$C_RED"    "$C_OFF" "$*" >&2; exit 1; }

# 各分支可用子版本（X = 该系列最新 LTS）
declare -A SUBVERS
SUBVERS[android12-5.10]="43 66 81 101 110 117 136 149 160 168 177 185 198 205 209 218 226 233 236 237 240 246 256 X"
SUBVERS[android13-5.15]="41 74 78 94 104 119 123 137 144 148 149 151 153 167 170 178 180 185 189 194 207 X"
SUBVERS[android14-6.1]="25 43 57 68 75 78 84 90 93 99 112 115 118 124 128 129 134 138 141 145 157 162 172 173 X"
SUBVERS[android15-6.6]="50 56 57 58 66 77 82 87 89 92 98 102 118 127 139 X"
SUBVERS[android16-6.12]="23 30 38 58 69 81 X"
SUBVERS[android17-6.18]="21 X"

# ------------------------------ 通用菜单 ------------------------------
# 用法: menu "提示语" "默认序号" "选项1" "选项2" ...  结果放 MENU_IDX
MENU_IDX=0
menu() {
    local prompt="$1"; local def="$2"; shift 2
    local opts=("$@")
    echo
    printf '%s%s%s\n' "$C_CYAN" "$prompt" "$C_OFF"
    local i
    for i in "${!opts[@]}"; do
        printf '  %s%d)%s %s\n' "$C_BOLD" $((i+1)) "$C_OFF" "${opts[i]}"
    done
    local c
    while true; do
        read -r -p "请输入序号 [1-${#opts[@]}]（默认 ${def}）: " c
        c="${c:-$def}"
        if [[ "$c" =~ ^[0-9]+$ ]] && (( c >= 1 && c <= ${#opts[@]} )); then
            MENU_IDX=$((c-1))
            printf '  %s→%s %s\n' "$C_GREEN" "$C_OFF" "${opts[MENU_IDX]}"
            return 0
        fi
        echo "无效输入，重试"
    done
}

yn() { # yn "提示" 默认值 -> 返回 0/1
    local p="$1" d="$2" a
    while true; do
        read -r -p "$p [y/n]（默认 $d）: " a
        a="${a:-$d}"
        case "${a,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) echo "请输入 y 或 n" ;;
        esac
    done
}

# --------------------- 自动识别云端 Actions 仓库 ---------------------
# 优先级：环境变量 > 当前目录 git remote > gh 登录用户下的 gki-kernel-builder
detect_actions_repo() {
    if [[ -n "${GKI_ACTIONS_REPO:-}" ]]; then
        printf '%s' "$GKI_ACTIONS_REPO"; return 0
    fi
    if command -v git >/dev/null 2>&1; then
        local r=""
        r=$(git config --get remote.origin.url 2>/dev/null || true)
        if [[ "$r" =~ github\.com[:/]+([^/]+)/(.+) ]]; then
            local o="${BASH_REMATCH[1]}" n="${BASH_REMATCH[2]}"
            n="${n%.git}"
            if [[ -n "$o" && -n "$n" ]]; then
                printf '%s/%s' "$o" "$n"; return 0
            fi
        fi
    fi
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        local u=""
        u=$(gh api user --jq '.login' 2>/dev/null || true)
        u="${u//[[:space:]]/}"
        if [[ -n "$u" ]]; then
            local hit=""
            hit=$(gh repo list "$u" --limit 100 --json nameWithOwner \
                  --jq '.[].nameWithOwner' 2>/dev/null \
                  | grep -i -m1 'gki-kernel-builder' || true)
            if [[ -n "$hit" ]]; then printf '%s' "$hit"; return 0; fi
            printf '%s/gki-kernel-builder' "$u"; return 0
        fi
    fi
    return 1
}

# ------------------------------ 交互式向导 ------------------------------
wizard() {
    printf '%s\n' "════════════════════════════════════════════"
    printf '%s   Droidspaces GKI 内核一键编译向导%s\n' "$C_BOLD" "$C_OFF"
    printf '%s\n' "════════════════════════════════════════════"
    echo
    warn "子版本号必须与手机当前内核完全一致，否则刷入变砖"
    echo "  查版本：adb shell cat /proc/version"
    echo "  示例输出 6.1.138-android14-11 → 选 Android 14 / 6.1 / 138"

    menu "① 选择 Android 与内核大版本" 3 \
        "Android 12 - 5.10" \
        "Android 13 - 5.15" \
        "Android 14 - 6.1   ← 小米 14 Ultra（澎湃OS 1/3 的 6.1 内核）" \
        "Android 15 - 6.6" \
        "Android 16 - 6.12  ⚠ 米系设备不可用" \
        "Android 17 - 6.18  ⚠ 新适配，先测试"
    case $MENU_IDX in
        0) AV=android12; KV=5.10 ;;
        1) AV=android13; KV=5.15 ;;
        2) AV=android14; KV=6.1  ;;
        3) AV=android15; KV=6.6  ;;
        4) AV=android16; KV=6.12 ;;
        5) AV=android17; KV=6.18 ;;
    esac

    local key="${AV}-${KV}"
    local subs=(${SUBVERS[$key]})
    menu "② 选择子版本号（${key}）" 1 "${subs[@]}"
    SUB="${subs[$MENU_IDX]}"

    if [[ "$KV" == "6.12" || "$KV" == "6.18" ]]; then
        warn "上游 README：6.12 编译产物米系设备无法使用；6.18 请谨慎"
        if [[ "$SLOT" == "678" || "$SLOT" == "123" || "$SLOT" == "345" ]]; then SLOT="on"; fi
    fi

    menu "③ 选择内置 root 方案" 1 \
        "ReSukiSU（推荐，本内核默认）" \
        "None（纯 GKI 内核，无 root）" \
        "Official（KernelSU 官方）"
    case $MENU_IDX in 0) KSU=ReSukiSU ;; 1) KSU=None ;; 2) KSU=Official ;; esac

    if [[ "$KV" == "6.12" || "$KV" == "6.18" ]]; then
        menu "④ Droidspaces 容器支持" 2 "on（开启）" "off（关闭）"
        case $MENU_IDX in 0) SLOT=on ;; 1) SLOT=off ;; esac
    else
        menu "④ Droidspaces 槽位（刷后 bootloop 请换其他槽位重试）" 1 \
            "678（推荐）" "123（备用）" "345（备用）" "off（关闭）"
        case $MENU_IDX in 0) SLOT=678 ;; 1) SLOT=123 ;; 2) SLOT=345 ;; 3) SLOT=off ;; esac
    fi

    echo
    printf '%s⑤ 可选功能%s\n' "$C_BOLD" "$C_OFF"
    if yn "  开启 CVE-2026-43499 rtmutex 修复链?" y; then CVE=true;  else CVE=false;  fi
    if yn "  开启 ZRAM LZ4KD 增强?（实验性，作者不推荐）" n; then ZRAM=true; else ZRAM=false; fi
    if [[ "$KSU" != "None" ]]; then
        if yn "  开启 KPM 模块支持?" n; then KPM=true; else KPM=false; fi
    else
        KPM=false
    fi

    echo
    printf '%s⑥ 编译方式%s\n' "$C_BOLD" "$C_OFF"
    menu "   选择编译方式" 1 \
        "本地编译（本机 Linux/WSL，需联网拉约 2.2GB 源码）" \
        "云端编译（GitHub Actions，本机网络差时首选）"
    if [[ $MENU_IDX -eq 1 ]]; then MODE=cloud; fi

    if [[ "$MODE" == "cloud" ]]; then
        if [[ -z "${GKI_ACTIONS_REPO:-}" ]]; then
            local auto=""
            auto=$(detect_actions_repo 2>/dev/null || true)
            if [[ -n "$auto" ]]; then
                printf '   检测到 Actions 仓库: %s%s%s\n' "$C_CYAN" "$auto" "$C_OFF"
                if yn "   用这个仓库跑云端编译?" y; then
                    GKI_ACTIONS_REPO="$auto"
                else
                    local r
                    read -r -p "   请输入 Actions 仓库（owner/repo）: " r
                    GKI_ACTIONS_REPO="${r:-$auto}"
                fi
            else
                warn "没检测到仓库。请先 Fork https://github.com/fuwawas/gki-kernel-builder 到自己账号"
                local r
                read -r -p "   请输入 Actions 仓库（owner/repo）: " r
                GKI_ACTIONS_REPO="$r"
            fi
        fi
        GKI_ACTIONS_REPO="${GKI_ACTIONS_REPO#https://github.com/}"
        GKI_ACTIONS_REPO="${GKI_ACTIONS_REPO%.git}"
        if yn "   云端跑完后自动等待并下载产物?" y; then WAIT=true; fi
    fi

    menu "⑦ LTO 模式（none 快一倍多，但镜像体积大）" 1 \
        "thin（脚本默认，约 45-60 分钟）" \
        "none（约 20-40 分钟，体积大）" \
        "full（最慢）"
    case $MENU_IDX in 0) LTO=thin ;; 1) LTO=none ;; 2) LTO=full ;; esac

    OUTDIR="${OUTDIR:-$PWD/gki-out}"

    echo
    printf '%s══════ 配置确认 ══════%s\n' "$C_BOLD" "$C_OFF"
    printf '  目标版本    : %s-%s-%s\n' "$AV" "$KV" "$SUB"
    printf '  root 方案   : %s\n' "$KSU"
    printf '  Droidspaces : %s\n' "$SLOT"
    printf '  CVE / ZRAM / KPM : %s / %s / %s\n' "$CVE" "$ZRAM" "$KPM"
    printf '  LTO         : %s\n' "$LTO"
    printf '  编译方式    : %s\n' "$MODE"
    if [[ "$MODE" == "local" ]]; then
        printf '  缓存目录    : %s（重编会复用源码）\n' "$CACHE_DIR"
    fi
    printf '  产物目录    : %s\n' "$OUTDIR"
    echo
    yn "确认无误，开始执行?" y || { echo "已取消"; exit 0; }
}

# ------------------------------ 参数模式 ------------------------------
usage() {
    sed -n '3,30p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'
    cat <<'EOF'

常用示例:
  ./gkibuild.sh                              交互式向导（推荐新手）
  ./gkibuild.sh -v android14-6.1-138        命令行直编
  ./gkibuild.sh -v android15-6.6-127 -s 123 指定槽位
  ./gkibuild.sh -v android14-6.1-157 --cloud --wait
  ./gkibuild.sh --list                      列出支持的版本

本地编译相关:
  --cache-dir <路径>      源码与工具缓存目录（默认 ~/.cache/gkibuild）
                          第二次编译会复用已下载的源码，不再重拉 2.2GB
  --out <路径>            产物输出目录（默认 ./gki-out）
  --no-deps               跳过依赖安装检查
EOF
    exit 0
}

if [[ $# -gt 0 ]]; then
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version) VERSION="$2"; shift 2 ;;
            -k|--ksu)     KSU="$2";     shift 2 ;;
            -s|--slot)    SLOT="$2";    shift 2 ;;
            -m|--mirror)  MIRROR="$2";  shift 2 ;;
            -o|--out)     OUTDIR="$2";  shift 2 ;;
            --cache-dir)  CACHE_DIR="$2"; shift 2 ;;
            --lto)        LTO="$2";     shift 2 ;;
            --tag)        SRC_TAG="$2"; shift 2 ;;
            --cloud-repo) GKI_ACTIONS_REPO="$2"; shift 2 ;;
            --cve)        CVE=true;   shift ;;
            --no-cve)     CVE=false;  shift ;;
            --zram)       ZRAM=true;  shift ;;
            --no-zram)    ZRAM=false; shift ;;
            --kpm)        KPM=true;   shift ;;
            --no-deps)    INSTALL_DEPS=false; shift ;;
            --cloud)      MODE=cloud; shift ;;
            --wait)       WAIT=true;  shift ;;
            -h|--help)    usage ;;
            --list)
                for k in android12-5.10 android13-5.15 android14-6.1 android15-6.6 android16-6.12 android17-6.18; do
                    printf '%-18s %s\n' "$k" "${SUBVERS[$k]}"
                done
                exit 0 ;;
            *) die "未知参数: $1（--help 看用法）" ;;
        esac
    done
    [[ -n "$VERSION" ]] || die "命令行模式需要 -v <版本>，或直接不带参数运行进入向导"
    [[ "$VERSION" =~ ^(android[0-9]+)-([0-9]+\.[0-9]+)-([0-9]+|X)$ ]] \
        || die "版本格式不对: $VERSION"
    AV="${BASH_REMATCH[1]}"; KV="${BASH_REMATCH[2]}"; SUB="${BASH_REMATCH[3]}"
else
    wizard
fi

# 6.12 / 6.18 只有 on/off 两种槽位，自动纠正命令行传入的 678/123/345
if [[ "$KV" == "6.12" || "$KV" == "6.18" ]]; then
    warn "上游 README：6.12 编译产物米系设备无法使用；6.18 请谨慎测试"
    if [[ "$SLOT" == "678" || "$SLOT" == "123" || "$SLOT" == "345" ]]; then SLOT="on"; fi
fi

OUTDIR="${OUTDIR:-$PWD/gki-out}"
mkdir -p "$OUTDIR"

echo
log "目标 ${AV}-${KV}-${SUB} | KSU=${KSU} | Droidspaces=${SLOT} | LTO=${LTO} | 模式=${MODE}"
echo

# ============================ 云端模式 ============================
if [[ "$MODE" == "cloud" ]]; then
    command -v gh >/dev/null 2>&1 || die "云端模式需要 gh CLI：https://cli.github.com"
    REPO="${GKI_ACTIONS_REPO:-}"
    if [[ -z "$REPO" ]]; then
        REPO=$(detect_actions_repo 2>/dev/null || true)
    fi
    REPO="${REPO#https://github.com/}"
    REPO="${REPO%.git}"
    [[ -n "$REPO" ]] || die "找不到 Actions 仓库。\
请先 Fork https://github.com/fuwawas/gki-kernel-builder 到自己账号，\
或用 --cloud-repo owner/repo 指定（例如 --cloud-repo zhangsan/gki-kernel-builder）"
    gh auth status >/dev/null 2>&1 || die "gh 未登录，先执行 gh auth login"
    gh repo view "$REPO" >/dev/null 2>&1 \
        || die "仓库 $REPO 不存在或你没有权限。若还没 Fork，先 Fork：https://github.com/fuwawas/gki-kernel-builder"
    ok "Actions 仓库: $REPO"

    log "触发 GitHub Actions: $REPO"
    BEFORE=$(gh run list --repo "$REPO" --limit 1 --json databaseId --jq '.[0].databaseId // 0')
    gh workflow run build-gki.yml --repo "$REPO" \
        -f android_version="$AV" -f kernel_version="$KV" -f sub_level="$SUB" \
        -f ksu_variant="$KSU" -f droidspaces="$SLOT" \
        -f cve_patch="$CVE" -f use_zram="$ZRAM" -f use_kpm="$KPM" -f lto_mode="$LTO"
    sleep 8
    RUN=$(gh run list --repo "$REPO" --limit 1 --json databaseId --jq '.[0].databaseId')
    [[ "$RUN" != "$BEFORE" ]] || die "未取到新 run ID，请到 Actions 页面确认"
    ok "已触发 run $RUN"
    echo "   https://github.com/$REPO/actions/runs/$RUN"

    if [[ "$WAIT" == "true" ]]; then
        log "等待完成（约 45-60 分钟，每 60 秒检查）..."
        while [[ "$(gh run view "$RUN" --repo "$REPO" --json status --jq '.status')" != "completed" ]]; do
            sleep 60
        done
        CONC=$(gh run view "$RUN" --repo "$REPO" --json conclusion --jq '.conclusion')
        if [[ "$CONC" == "success" ]]; then
            ok "编译成功，下载到 $OUTDIR"
            gh run download "$RUN" --repo "$REPO" --dir "$OUTDIR"
            find "$OUTDIR" -maxdepth 3 -type f \( -name '*.zip' -o -name 'Image' \) -print
        else
            die "编译失败（$CONC）：gh run view $RUN --repo $REPO --log-failed"
        fi
    fi
    exit 0
fi

# ============================ 本地模式 ============================
[[ "$(uname -s)" == "Linux" ]] || die "本地模式需要 Linux / WSL；Windows 请选云端模式"

if [[ "$INSTALL_DEPS" == "true" ]]; then
    # root（含 Docker 容器）里没有 sudo，且 sudo 本身也用不上
    SUDO="sudo"
    if [[ "$(id -u)" -eq 0 ]] || ! command -v sudo >/dev/null 2>&1; then SUDO=""; fi

    log "检查依赖"
    MISSING=()
    for c in git curl clang lld cpio python3 zstd tar; do
        command -v "$c" >/dev/null 2>&1 || MISSING+=("$c")
    done
    if [[ ${#MISSING[@]} -gt 0 ]]; then
        warn "缺少: ${MISSING[*]}"
        if   command -v apt-get >/dev/null 2>&1; then
            $SUDO apt-get update -qq
            $SUDO apt-get install -y git curl make gcc g++ build-essential libssl-dev bison flex \
                libelf-dev dwarves ccache python3 clang lld bc rsync cpio perl patch zip gawk zstd
        elif command -v dnf >/dev/null 2>&1; then
            $SUDO dnf install -y git curl make gcc gcc-c++ openssl-devel bison flex \
                elfutils-libelf-devel dwarves ccache python3 clang lld bc rsync cpio perl patch zip gawk zstd tar
        elif command -v pacman >/dev/null 2>&1; then
            $SUDO pacman -S --needed --noconfirm git curl make gcc base-devel openssl bison flex \
                libelf dwarves ccache python clang lld bc rsync cpio perl zip zstd
        else
            die "请手动安装: ${MISSING[*]}"
        fi
    fi
    ok "依赖就绪"
fi

pick_mirror() {
    local probe="https://github.com/404-GCross/Droidspaces_GKI_Buildin_Local/raw/main/README.md"
    local best="" best_ms=999999 m ms
    for m in "${UPSTREAM_MIRRORS[@]}"; do
        ms=$(curl -o /dev/null -sS -m 20 -w '%{time_total}' "${m}${probe}" 2>/dev/null || echo 999)
        if awk -v a="$ms" -v b="$best_ms" 'BEGIN{exit !(a+0 < b+0)}'; then
            best_ms="$ms"; best="$m"
        fi
    done
    echo "$best"
}
if [[ -z "$MIRROR" ]]; then
    log "测速挑选 GitHub 镜像..."
    MIRROR=$(pick_mirror)
    [[ -n "$MIRROR" ]] && ok "选用 $MIRROR" || warn "镜像均不可用，改为直连"
fi

WORKROOT="$CACHE_DIR"
mkdir -p "$WORKROOT"

# 本地优先：如果本脚本就躺在已 clone 的仓库里，直接用仓库自带的工具，
# 不再重复 clone 一份（省时间，也避免两边版本漂移）
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLDIR="$WORKROOT/Droidspaces_GKI_Buildin_Local"
if [[ -f "$SELF_DIR/build_kernel.sh" && -d "$SELF_DIR/scripts" ]]; then
    TOOLDIR="$SELF_DIR"
    ok "复用当前仓库的编译工具：$TOOLDIR"
else
    if [[ ! -f "$TOOLDIR/build_kernel.sh" ]]; then
        log "获取编译工具"
        git clone --depth 1 "https://github.com/${TOOL_REPO}.git" "$TOOLDIR" 2>/dev/null \
            || git clone --depth 1 "${MIRROR}https://github.com/${TOOL_REPO}.git" "$TOOLDIR" \
            || die "克隆失败，换一个 --mirror 试试"
    fi
    ok "编译工具就绪：$TOOLDIR"
fi
chmod +x "$TOOLDIR/build_kernel.sh"

SRCDIR="$WORKROOT/src/${AV}-${KV}-${SUB}"
if [[ -d "$SRCDIR/common" || -f "$SRCDIR/Makefile" ]]; then
    ok "源码已存在: $SRCDIR"
else
    log "下载源码 ${AV}-${KV}-${SUB}（约 2.2GB）"
    DL="$WORKROOT/dl-${AV}-${KV}-${SUB}"
    mkdir -p "$DL"
    API="https://api.github.com/repos/${SRC_REPO}/releases/tags/${SRC_TAG}"
    ASSETS=$(curl -sSL --max-time 60 "$API" | python3 -c "
import json,sys,re
d=json.load(sys.stdin)
pat=re.compile(r'^kernel-full-source-${AV}-${KV}-${SUB}[-.].*')
for a in d.get('assets',[]):
    if pat.match(a['name']): print(a['name']+'\t'+a['browser_download_url'])
")
    [[ -n "$ASSETS" ]] || die "未找到源码包：版本有误或 --tag 过期"
    while IFS=$'\t' read -r name url; do
        [[ -n "$name" ]] || continue
        dest="$DL/$name"
        if [[ -s "$dest" ]]; then ok "已存在 $name"; continue; fi
        curl -fL --retry 3 --retry-delay 5 -o "$dest" "${MIRROR}${url}" \
            || curl -fL --retry 3 --retry-delay 5 -o "$dest" "$url" \
            || die "下载失败: $name"
        ok "$name 完成"
    done <<< "$ASSETS"

    mapfile -t PARTS < <(ls -1v "$DL"/* | grep -E '\.part[0-9]+$')
    [[ ${#PARTS[@]} -gt 0 ]] || die "未找到 .partN 分卷"
    cat "${PARTS[@]}" > "$DL/kernel.tar.zst"
    MAGIC=$(head -c 4 "$DL/kernel.tar.zst" | od -An -tx1 | tr -d ' \n')
    [[ "$MAGIC" == "28b52ffd" ]] || die "合并后不是 zstd (magic=$MAGIC)"

    mkdir -p "$SRCDIR"
    tar -I zstd -xf "$DL/kernel.tar.zst" -C "$SRCDIR"
    shopt -s dotglob nullglob
    items=("$SRCDIR"/*)
    if [[ ${#items[@]} -eq 1 && -d "${items[0]}" ]]; then SRCDIR="${items[0]}"; fi
    shopt -u dotglob nullglob
    [[ -d "$SRCDIR/common" || -f "$SRCDIR/Makefile" ]] || die "解压后无 common/ 或 Makefile"
    ok "源码就绪: $SRCDIR"
fi

log "生成构建配置"
cat > "$TOOLDIR/.build_config" << EOF
APP_LANG="zh"
ANDROID_VERSION="${AV}"
KERNEL_VERSION="${KV}"
SUB_LEVEL="${SUB}"
OS_PATCH_LEVEL=""
REVISION=""
KSU_VARIANT="${KSU}"
KSU_BRANCH="${KSU_BRANCH}"
CUSTOM_VERSION=""
BUILD_TIME=""
USE_ZRAM="${ZRAM}"
USE_KPM="${KPM}"
USE_REKERNEL="false"
CVE_2026_43499_PATCH="${CVE}"
DROIDSPACES="${SLOT}"
KERNEL_SOURCE="${SRCDIR}"
KERNEL_SOURCE_TARBALL=""
OUTPUT_DIR="${TOOLDIR}/build/out"
PACKAGE_BOOT="true"
EOF

log "开始编译（LTO=${LTO}，通常 45-60 分钟）"
cd "$TOOLDIR"
LTO_MODE="$LTO" ./build_kernel.sh --quick < /dev/null || die "编译失败，看上方报错"

log "收集产物到 $OUTDIR"
find "$TOOLDIR/build/out" -maxdepth 2 -type f \
    \( -name '*.zip' -o -name 'Image' -o -name 'Image.gz' -o -name 'Image.lz4' \) \
    -exec cp -v {} "$OUTDIR/" \; 2>/dev/null || true

echo
ok "完成，产物："
ls -lh "$OUTDIR"
echo
warn "刷机前备份原厂 boot；小米还需处理 vbmeta（命令见 README）"
