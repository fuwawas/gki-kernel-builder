#Requires -Version 5.1
# GKI 内核一键编译工具（Droidspaces / KernelSU）
# 双击同目录的 "启动编译.bat" 运行本脚本

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$REPO_NAME  = "gki-kernel-builder"
$GH_REPO    = ""
$GH_USER    = ""

# 自动读取当前 gh 登录用户名，拼出 owner/repo，这样换人用也不用改脚本
function Resolve-Repo {
    $script:GH_REPO = ""
    try {
        $u = (& gh api user --jq ".login" 2>$null)
        if ($u) { $u = $u.Trim() }
        if ($u -and $u -notmatch '\s') {
            $script:GH_USER = $u
            $script:GH_REPO = "$u/$REPO_NAME"
        }
    } catch { }
}
Resolve-Repo

$SCRIPT_URL = "https://raw.githubusercontent.com/$GH_REPO/main/gkibuild.sh"

$Branches = @(
    @{ Av = "android12"; Kv = "5.10"; Name = "Android 12 - 5.10" }
    @{ Av = "android13"; Kv = "5.15"; Name = "Android 13 - 5.15" }
    @{ Av = "android14"; Kv = "6.1";  Name = "Android 14 - 6.1   <- 小米 14 Ultra（澎湃OS 的 6.1 内核）" }
    @{ Av = "android15"; Kv = "6.6";  Name = "Android 15 - 6.6" }
    @{ Av = "android16"; Kv = "6.12"; Name = "Android 16 - 6.12  （米系设备不可用）" }
    @{ Av = "android17"; Kv = "6.18"; Name = "Android 17 - 6.18  （新适配，先测试）" }
)

function Show-Title($text) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
    Write-Host ""
}

function Get-Choice {
    param([string]$Prompt, [string[]]$Options, [int]$Default = 1)
    Write-Host $Prompt -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("  {0}) {1}" -f ($i + 1), $Options[$i])
    }
    while ($true) {
        $c = Read-Host "  请输入序号 [1-$($Options.Count)]（默认 $Default）"
        if ([string]::IsNullOrWhiteSpace($c)) { $c = "$Default" }
        if ($c -match '^\d+$') {
            $n = [int]$c
            if ($n -ge 1 -and $n -le $Options.Count) {
                Write-Host ("  -> " + $Options[$n - 1]) -ForegroundColor Green
                return $n
            }
        }
        Write-Host "  无效输入，请重试" -ForegroundColor Yellow
    }
}

function Get-YesNo {
    param([string]$Prompt, [bool]$Default = $true)
    $hint = if ($Default) { "Y/n" } else { "y/N" }
    while ($true) {
        $a = Read-Host "  $Prompt [$hint]"
        if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
        switch -Regex ($a.Trim().ToLower()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default     { Write-Host "  请输入 y 或 n" -ForegroundColor Yellow }
        }
    }
}

function Test-Gh {
    $cmd = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $cmd) { return "missing" }
    & gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return "notlogin" }
    return "ok"
}

function Test-Wsl {
    $cmd = Get-Command wsl -ErrorAction SilentlyContinue
    if (-not $cmd) { return "missing" }
    try {
        $out = & wsl -l -q 2>$null
        if ([string]::IsNullOrWhiteSpace(($out -join ""))) { return "nodistro" }
        return "ok"
    } catch {
        return "error"
    }
}

function Show-VersionList {
    Clear-Host
    Show-Title "支持的内核版本"
    Write-Host "  android12-5.10   43 66 81 101 110 117 136 149 160 168 177 185 198" -ForegroundColor White
    Write-Host "                   205 209 218 226 233 236 237 240 246 256 X"
    Write-Host ""
    Write-Host "  android13-5.15   41 74 78 94 104 119 123 137 144 148 149 151 153 167"
    Write-Host "                   170 178 180 185 189 194 207 X"
    Write-Host ""
    Write-Host "  android14-6.1    25 43 57 68 75 78 84 90 93 99 112 115 118 124 128" -ForegroundColor Yellow
    Write-Host "                   129 134 138 141 145 157 162 172 173 X    <- 小米 14 Ultra" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  android15-6.6    50 56 57 58 66 77 82 87 89 92 98 102 118 127 139 X"
    Write-Host ""
    Write-Host "  android16-6.12   23 30 38 58 69 81 X      （米系设备不可用）" -ForegroundColor DarkGray
    Write-Host "  android17-6.18   21 X                     （新适配，先测试）" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  X = 该系列最新 LTS 版本" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  子版本号必须与手机当前内核一致，查询命令：" -ForegroundColor Red
    Write-Host "    adb shell cat /proc/version" -ForegroundColor White
    Write-Host ""
    Read-Host "按回车返回"
}

function Show-EnvCheck {
    Clear-Host
    Show-Title "环境检查"
    $g = Test-Gh
    Write-Host "  gh (GitHub CLI，云端编译需要)" -ForegroundColor Cyan
    switch ($g) {
        "ok"       { Write-Host "    状态：已安装且已登录" -ForegroundColor Green }
        "notlogin" { Write-Host "    状态：已安装但未登录，请执行 gh auth login" -ForegroundColor Yellow }
        "missing"  { Write-Host "    状态：未安装，下载地址 https://cli.github.com" -ForegroundColor Red }
    }
    Write-Host ""
    $w = Test-Wsl
    Write-Host "  WSL (本地编译需要)" -ForegroundColor Cyan
    switch ($w) {
        "ok"       { Write-Host "    状态：已安装" -ForegroundColor Green; & wsl -l -q 2>$null }
        "nodistro" { Write-Host "    状态：已装 WSL 但没有 Linux 发行版，请从应用商店装 Ubuntu" -ForegroundColor Yellow }
        "missing"  { Write-Host "    状态：未安装，管理员 PowerShell 执行 wsl --install 后重启" -ForegroundColor Yellow }
        "error"    { Write-Host "    状态：WSL 存在但无法执行（可能被安全策略拦截），建议改用云端编译" -ForegroundColor Yellow }
    }
    Write-Host ""
    Read-Host "按回车返回"
}

function Set-Repo {
    Clear-Host
    Show-Title "设置目标仓库"
    Write-Host "  云端编译需要一个你自己的 GitHub 仓库来跑 Actions。"
    Write-Host "  格式：GitHub用户名/仓库名"
    Write-Host ""
    if ($GH_REPO) { Write-Host ("  当前：" + $GH_REPO) -ForegroundColor Cyan }
    Write-Host ""
    $r = Read-Host "  请输入（留空则自动检测当前 gh 登录用户）"
    if ([string]::IsNullOrWhiteSpace($r)) {
        Resolve-Repo
    } else {
        $script:GH_REPO = $r.Trim()
    }
    $script:SCRIPT_URL = "https://raw.githubusercontent.com/$($script:GH_REPO)/main/gkibuild.sh"
    Write-Host ""
    if ($script:GH_REPO) { Write-Host ("  已设为：" + $script:GH_REPO) -ForegroundColor Green }
    else { Write-Host "  未能自动检测，请先执行 gh auth login" -ForegroundColor Yellow }
    Write-Host ""
    Read-Host "按回车返回"
}

function Invoke-Build {
    Clear-Host
    Show-Title "选择 Android 与内核大版本"
    $names = $Branches | ForEach-Object { $_.Name }
    $pick = Get-Choice "① 选择 Android 与内核大版本" $names 3
    $b = $Branches[$pick - 1]
    $AV = $b.Av; $KV = $b.Kv

    Write-Host ""
    while ($true) {
        $SUB = Read-Host "② 输入子版本号（如 138，或 X 取最新 LTS）"
        if ($SUB -match '^(\d+|X)$') { break }
        Write-Host "  格式不对，请输入数字或 X" -ForegroundColor Yellow
    }

    $ksuPick = Get-Choice "③ 选择内置 root 方案" @("ReSukiSU（推荐）", "None（纯 GKI 内核，无 root）", "Official（KernelSU 官方）") 1
    $KSU = @("ReSukiSU", "None", "Official")[$ksuPick - 1]

    if ($KV -eq "6.12" -or $KV -eq "6.18") {
        $slotPick = Get-Choice "④ Droidspaces 容器支持" @("on（开启）", "off（关闭）") 1
        $SLOT = @("on", "off")[$slotPick - 1]
    } else {
        $slotPick = Get-Choice "④ Droidspaces 槽位（刷后卡开机请换其他槽位重编）" @("678（推荐）", "123（备用）", "345（备用）", "off（关闭）") 1
        $SLOT = @("678", "123", "345", "off")[$slotPick - 1]
    }

    $modePick = Get-Choice "⑤ 选择编译方式" @("云端编译（GitHub Actions，不需要 WSL，推荐）", "本地编译（需要电脑已装 WSL / Ubuntu）") 1
    $MODE = @("cloud", "local")[$modePick - 1]

    $CVE = "true"; $ZRAM = "false"; $KPM = "false"; $LTO = "thin"
    Write-Host ""
    if (Get-YesNo "是否修改高级选项？（默认 CVE 开 / ZRAM 关 / KPM 关 / LTO thin）" $false) {
        $CVE  = if (Get-YesNo "  开启 CVE-2026-43499 rtmutex 修复链？" $true) { "true" } else { "false" }
        $ZRAM = if (Get-YesNo "  开启 ZRAM LZ4KD 增强？（实验性，作者不推荐）" $false) { "true" } else { "false" }
        $KPM  = if (Get-YesNo "  开启 KPM 模块支持？" $false) { "true" } else { "false" }
        $ltoPick = Get-Choice "  LTO 模式" @("thin（脚本默认，45-60 分钟）", "none（20-40 分钟，体积大）", "full（最慢）") 1
        $LTO = @("thin", "none", "full")[$ltoPick - 1]
    }

    Clear-Host
    Show-Title "配置确认"
    Write-Host ("  目标版本    : {0}-{1}-{2}" -f $AV, $KV, $SUB)
    Write-Host ("  root 方案   : {0}" -f $KSU)
    Write-Host ("  Droidspaces : {0}" -f $SLOT)
    Write-Host ("  CVE / ZRAM / KPM : {0} / {1} / {2}" -f $CVE, $ZRAM, $KPM)
    Write-Host ("  LTO         : {0}" -f $LTO)
    Write-Host ("  编译方式    : {0}" -f $(if ($MODE -eq "cloud") { "云端" } else { "本地" }))
    Write-Host ""
    if (-not (Get-YesNo "确认开始？" $true)) { return }

    $ver = "$AV-$KV-$SUB"
    Write-Host ""

    if ($MODE -eq "cloud") {
        $g = Test-Gh
        if ($g -eq "missing")  { Write-Host "未检测到 gh，请先安装：https://cli.github.com" -ForegroundColor Red; Read-Host "按回车返回"; return }
        if ($g -eq "notlogin") { Write-Host "gh 未登录，请先执行：gh auth login" -ForegroundColor Red; Read-Host "按回车返回"; return }
        if (-not $GH_REPO)     { Write-Host "未设置云端仓库，请回主菜单选 5 设置" -ForegroundColor Red; Read-Host "按回车返回"; return }

        Write-Host "正在触发 GitHub Actions ..." -ForegroundColor Cyan
        $before = (& gh run list --repo $GH_REPO --limit 1 --json databaseId --jq ".[0].databaseId") 2>$null
        & gh workflow run build-gki.yml --repo $GH_REPO `
            -f android_version=$AV -f kernel_version=$KV -f sub_level=$SUB `
            -f ksu_variant=$KSU -f droidspaces=$SLOT `
            -f cve_patch=$CVE -f use_zram=$ZRAM -f use_kpm=$KPM -f lto_mode=$LTO
        if ($LASTEXITCODE -ne 0) {
            Write-Host "触发失败，请检查仓库名与权限" -ForegroundColor Red
            Read-Host "按回车返回"; return
        }
        Start-Sleep -Seconds 6
        $runId = (& gh run list --repo $GH_REPO --limit 1 --json databaseId --jq ".[0].databaseId") 2>$null
        $url = "https://github.com/$GH_REPO/actions/runs/$runId"
        Write-Host ""
        Write-Host "已触发！编译约 45-60 分钟" -ForegroundColor Green
        Write-Host "进度页面：$url" -ForegroundColor Cyan
        if (Get-YesNo "是否在浏览器中打开进度页面？" $true) { Start-Process $url }
        Write-Host ""
        Read-Host "按回车返回"
    } else {
        $w = Test-Wsl
        if ($w -eq "missing") {
            Write-Host "未检测到 WSL。" -ForegroundColor Red
            Write-Host "请以管理员身份打开 PowerShell 执行：wsl --install" -ForegroundColor Yellow
            Write-Host "安装完成后重启电脑，再运行本工具。" -ForegroundColor Yellow
            Read-Host "按回车返回"; return
        }
        if ($w -eq "nodistro") {
            Write-Host "WSL 已安装但没有 Linux 发行版，请从 Microsoft Store 安装 Ubuntu。" -ForegroundColor Yellow
            Read-Host "按回车返回"; return
        }
        Write-Host "正在 WSL 中执行编译，请耐心等待（约 45-60 分钟）..." -ForegroundColor Cyan
        Write-Host ""
        $cmd = "curl -sL -o ~/gkibuild.sh $SCRIPT_URL && chmod +x ~/gkibuild.sh && ~/gkibuild.sh -v $ver -k $KSU -s $SLOT --lto $LTO -o ~/gki-out"
        try {
            & wsl bash -lc $cmd
        } catch {
            Write-Host "调用 WSL 失败：$($_.Exception.Message)" -ForegroundColor Red
            Write-Host "若 WSL 被安全策略拦截，请改用云端编译方式。" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "执行结束。产物应在 WSL 的 ~/gki-out 目录" -ForegroundColor Cyan
        Read-Host "按回车返回"
    }
}

function Invoke-Download {
    Clear-Host
    Show-Title "下载最近一次编译产物"
    if ((Test-Gh) -ne "ok") {
        Write-Host "需要 gh 且已登录：https://cli.github.com" -ForegroundColor Red
        Read-Host "按回车返回"; return
    }
    if (-not $GH_REPO) {
        Write-Host "未设置云端仓库，请回主菜单选 5 设置" -ForegroundColor Red
        Read-Host "按回车返回"; return
    }
    $dir = Join-Path $HOME "kernel_out"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $runId = (& gh run list --repo $GH_REPO --limit 1 --json databaseId --jq ".[0].databaseId") 2>$null
    Write-Host "最近一次运行：$runId"
    & gh run download $runId --repo $GH_REPO --dir $dir
    Write-Host ""
    Write-Host "已下载到：$dir" -ForegroundColor Green
    Get-ChildItem -Path $dir -Recurse -File | ForEach-Object { Write-Host ("  " + $_.FullName) }
    Write-Host ""
    Read-Host "按回车返回"
}

# ---------------- 主循环 ----------------
while ($true) {
    Clear-Host
    Show-Title "GKI 内核一键编译工具  (Droidspaces / KernelSU)"
    if ($GH_REPO) {
        Write-Host ("  云端仓库: " + $GH_REPO) -ForegroundColor DarkCyan
    } else {
        Write-Host "  云端仓库: 未设置（选 5 自动检测或手动填写）" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  [1] 开始编译" -ForegroundColor Green
    Write-Host "  [2] 查看支持的内核版本"
    Write-Host "  [3] 下载最近一次编译产物"
    Write-Host "  [4] 检查环境 (gh / WSL)"
    Write-Host "  [5] 设置 / 刷新云端仓库"
    Write-Host "  [0] 退出"
    Write-Host ""
    $c = Read-Host "请选择 [0-5]"
    switch ($c) {
        "1" { Invoke-Build }
        "2" { Show-VersionList }
        "3" { Invoke-Download }
        "4" { Show-EnvCheck }
        "5" { Set-Repo }
        "0" { exit 0 }
        default { Write-Host "无效选择" -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
    }
}
