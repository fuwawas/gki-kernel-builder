# GKI 内核一键编译（Droidspaces + KernelSU）

给 Android 手机编译带 **Droidspaces 容器支持** 和 **内置 root** 的 GKI 内核。

- **云端编译**：编译在 GitHub 的服务器上跑，你电脑只负责点选，不需要装 Linux
- **本地编译**：有机子在跑 Linux / WSL / Docker 的话，也能在本机编
- **源码会缓存**：第一次拉约 2.2GB，之后重编（比如换槽位）不用再下载

原始脚本来自 [404-GCross/Droidspaces_GKI_Buildin_Local](https://github.com/404-GCross/Droidspaces_GKI_Buildin_Local)，
本仓库做了非交互式改造（原脚本是纯交互菜单，无法自动化）。

> **不想看网页版说明？** 仓库里有 `开始之前先看我.md`（完整离线教程）
> 和 `快速指引.txt`（Windows 双击就能看的精简版）。下载整包的话看这两个就行。

---

## 零、开始前：确认你的内核版本

**这一步最重要，填错就是白编一趟。**

手机打开 USB 调试，电脑执行：

```bash
adb shell cat /proc/version
```

或者：设置 → 我的设备 → 全部参数 → 内核版本

输出类似：

```
Linux version 6.1.138-android14-11-...
```

拆成三段：

```
Linux version 6.1.138-android14-11-...
              │││     │
              │││     └─ android14 → 表单第 1 项：Android 内核分支前缀
              │└└── 138          → 表单第 3 项：子版本号（必填）
              └─── 6.1           → 表单第 2 项：内核主线版本
```

| 输出里的这段 | 表单里对应的字段 | 填什么 |
|---|---|---|
| `android14` | Android 内核分支前缀 | `android14` |
| `6.1` | 内核主线版本 | `6.1` |
| `138` | 子版本号 | `138` |

懒得记就只看一个字串：`6.1.138` → 表单填 `android14` + `6.1` + `138`。

> ⚠️ **子版本号必须和手机上完全一致**，错一位就是刷入黑屏/不开机。
> `138` 和 `157` 是两个不同的东西，别凭印象填。

---

## 一、准备工作（只做一次，约 1 分钟）

### 1. 把本仓库 Fork 到你自己的 GitHub 账号

点本页右上角 **Fork** 按钮，其余全部保持默认（**仓库名别改**，改了自动化会找不到）。

> 为什么必须 Fork：编译是在 GitHub Actions 上跑的，得用**你自己账号下**的仓库，
> 否则没有权限启动任务，配额也记在别人账上。

### 2. ⚠️ 手动启用 Actions（不做这步一定失败）

GitHub 对 fork 来的仓库**默认禁用 Actions**。

操作：进你自己仓库的 **Actions** 标签页 → 看到黄色提示条 → 点绿色按钮
**「I understand my workflows, go ahead and enable them」**。

只做一次，之后再编译就不用管了。

---

## 二、四种用法，挑最省事的

| 你的情况 | 用哪个 | 本机要装什么 |
|---|---|---|
| 有 GitHub 账号，不想折腾环境 | **🟢 方案 A：纯网页** | 什么都不用装 |
| 纯 Windows，想懂更多操作 | 🟡 方案 B：Windows 双击 | gh CLI |
| 有 WSL / Linux | 🔵 方案 C：命令行 | 依赖由脚本自动装 |
| 有 Docker，不想污染本机环境 | 🟣 方案 D：Docker | Docker |
| Windows 且没 WSL 没 Docker | 只能选 A | — |

> **`gkibuild.sh` 是自举的**：它会自己 clone 编译工具、自己下载内核源码，
> 所以方案 C 只拿这一个文件也能跑，不必 clone 整个仓库。

### 🟢 方案 A：纯网页点两下（推荐，零安装零命令行）

准备做完之后，**不用装任何东西**，一个浏览器就够，手机浏览器也行。

1. 打开你自己 fork 的仓库 → **Actions** 标签页
2. 左侧列表点 **Build GKI Kernel (Droidspaces)**
3. 右上角点 **Run workflow** ▾ 展开下拉框
4. 按下表填（大部分留默认就行），点绿色 **Run workflow** 按钮

| 字段 | 怎么填 |
|---|---|
| `Android 内核分支前缀` | 看下面对照表，一般 `android14` |
| `内核主线版本` | 一般 `6.1` |
| `子版本号` | **必填**。手机 `adb shell cat /proc/version` 里第三段数字，如 `138` |
| `内置 root 方案` | `ReSukiSU`（推荐）/ `None` / `Official` |
| `Droidspaces 槽位` | `678`（先试这个） |
| `CVE-2026-43499 修复链` | 勾上 |
| `ZRAM LZ4KD` | 别勾，作者不推荐 |
| `LTO 模式` | `thin` 稳妥（约 30–50 分钟）；想快选 `none`（约 20–30 分钟，体积大） |
| 其余 | 全部留默认 |

5. 等 30 分钟左右刷新页面。**跑完在 run 页面中部会直接显示回显参数 + 复制即用的刷机命令**，
   不用去翻 Artifacts。

### 🟡 方案 B：Windows 双击（适合反复编译）

比方案 A 多一步，但能自动帮你下载产物。

1. 装 [gh CLI](https://cli.github.com) → 命令行执行 `gh auth login`（一路回车，浏览器登录）
2. 把 `启动编译.bat` 和 `build-gki.ps1` 下载到**同一个文件夹**
3. 双击 `启动编译.bat`，按菜单选版本

> 脚本会自动用你 gh 登录的用户名拼出 `你的用户名/gki-kernel-builder`。
> Fork 时改了仓库名的话，主菜单选 `5` 手动填。

### 🔵 方案 C：Linux / WSL 命令行（还能本机编译）

云端跑：**不用 Fork，不用 gh**，一条命令：

```bash
curl -sL -o gkibuild.sh https://raw.githubusercontent.com/fuwawas/gki-kernel-builder/main/gkibuild.sh
chmod +x gkibuild.sh
./gkibuild.sh
```

本机跑（需要 WSL/Ubuntu，联网拉约 2.2GB 源码）：

```bash
./gkibuild.sh -v android14-6.1-138          # 命令行直编
./gkibuild.sh --list                        # 查看支持的所有版本
```

不带参数运行会进交互式向导：选大版本 → 选子版本 → 选 root → 选槽位 → 开始。

源码和工具缓存在 `~/.cache/gkibuild`；**换槽位重编不会再重新下载源码**。
想换个位置（比如系统盘紧张）：

```bash
./gkibuild.sh -v android14-6.1-138 --cache-dir /mnt/d/kernel-cache
```

如果你就是在 clone 下来的本仓库目录里运行，脚本会直接复用仓库里自带的
`build_kernel.sh` / `config` / 补丁，**不会再 clone 一份**。

### 🟣 方案 D：Docker（本机不装编译依赖）

```bash
./docker-run.sh -v android14-6.1-138
```

不带参数进交互式向导。产物落在当前目录 `gki-out/`。

> 要求：≥ 4 核、≥ 16GB 内存、≥ 40GB 可用磁盘。
> **Docker Desktop 用户先去 Settings → Resources 把内存调到 8GB 以上**，
> 默认 2GB 一定编译失败。

> 国内网络拉不动 `raw.githubusercontent.com` 的话，用镜像：
> `https://ghproxy.net/https://raw.githubusercontent.com/fuwawas/gki-kernel-builder/main/gkibuild.sh`

不带参数运行会进交互式向导：选大版本 → 选子版本 → 选 root → 选槽位 → 编译。

命令行模式：

```bash
./gkibuild.sh -v android14-6.1-138
./gkibuild.sh -v android15-6.6-127 -s 123
./gkibuild.sh --list          # 查看所有支持的版本
```

---

## 三、可以选的项

| 选项 | 说明 |
|---|---|
| **root 方案** | `ReSukiSU`（推荐）/ `None`（纯内核无 root）/ `Official` |
| **Droidspaces 槽位** | `678`（推荐）/ `123` / `345` / `off` |
| **CVE 修复链** | CVE-2026-43499 rtmutex，默认开 |
| **ZRAM LZ4KD** | 实验性，作者不推荐，默认关 |
| **KPM** | 默认关 |
| **LTO** | `thin`（默认，45-60 分钟）/ `none`（20-40 分钟，体积大） |

### 槽位是什么，刷完卡开机怎么办

GKI 设备要跑容器必须打开 6 个内核配置，但这会破坏内核 ABI，导致厂商驱动模块加载失败、开不了机。
三个槽位是三种不同的绕开方案，**不保证哪个适配你的机型**。

刷入后卡在开机动画 → 刷回原厂 boot → 换个槽位重新编译（678 → 123 → 345）。

---

## 四、刷机须知（风险自负）

1. **先备份原厂 boot**，没备份别动手：
   ```bash
   adb shell su -c "dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot_stock.img"
   adb pull /sdcard/boot_stock.img
   ```

2. 小米机型通常还要处理 vbmeta：
   ```bash
   fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
   ```

3. 刷入：Recovery 里刷 AnyKernel3 的 zip，或 `fastboot flash boot Image`

4. 救砖：
   - 开机第一屏后**连按音量减 3 次**（按-松-按-松-按-松）进 KernelSU 安全模式，卸载问题模块
   - `adb shell su -c "ksud module uninstall <id>"`
   - 最后手段：`fastboot flash boot boot_stock.img` 刷回原厂

---

## 五、已知限制

- **Android 16 / 6.12**：上游明确说明编译产物**米系设备无法使用**，别给自己小米编 6.12
- **Android 17 / 6.18**：新适配，先小范围测试
- **SuSFS 与 Droidspaces 官方明确不兼容**，本方案不含 SuSFS

---

## 六、常见问题

**Q：双击 bat 一闪而过 / 报错？**
确认 `build-gki.ps1` 和 `启动编译.bat` 在**同一个文件夹**。

**Q：提示 gh 未登录？**
PowerShell 里执行 `gh auth login`。

**Q：提示找不到仓库？**
回主菜单选 `5`，确认显示的仓库名是你自己的（如 `zhangsan/gki-kernel-builder`）。
如果 Fork 时改了名字，手动填正确的。

**Q：脚本触发了，但 Actions 页面一片空白 / 一直不跑？**
回到第 1 步，Fork 后没有手动启用 Actions。去 Actions 标签页点那个绿色按钮启用即可。

**Q：显示 403 / Resource not accessible？**
说明你 gh 登录的账号和 Fork 到的账号不是同一个，或者仓库是私有可见性。
`gh auth status` 看当前登录账号。

**Q：换槽位重编，还要再下载那 2.2GB 吗？**
不用。源码缓存在 `~/.cache/gkibuild`（或你 `--cache-dir` 指定的位置），
第二次开始直接复用。

**Q：Docker 编译跑到一半被杀 / 报内存不足？**
Docker Desktop 默认只给 2GB，不够。Settings → Resources → Memory 调到 8GB 以上。

**Q：编译要多久？**
云端约 30-50 分钟（LTO=thin）。本机看 CPU 核数，一般 30-60 分钟。
选 `--lto none` 能快一档，代价是镜像体积变大。

**Q：免费额度够吗？**
GitHub 免费账号每月 2000 分钟 Actions 时长，一次编译约 30-50 分钟，一个月能编几十次。

---

## 七、文件说明

| 文件 | 用途 |
|---|---|
| `开始之前先看我.md` | **完整离线教程**，不想看网页就看这个 |
| `快速指引.txt` | 精简版，Windows 双击即可查看 |
| `启动编译.bat` | Windows 双击入口（纯英文，规避中文 bat 的编码坑） |
| `build-gki.ps1` | Windows 端菜单程序，负责选版本 + 调 gh |
| `gkibuild.sh` | Linux / WSL 端一键脚本（自举 + 向导 + 命令行三种用法） |
| `docker-run.sh` | Docker 一键编译，本机不用装任何依赖 |
| `Dockerfile` | Docker 镜像定义（含 bazelisk） |
| `.github/workflows/build-gki.yml` | 云端编译工作流 |

脚本部分遵循 GPL v2，版权归原作者 404-GCross。内核源码、KernelSU 等组件各自遵循其原始许可证。
