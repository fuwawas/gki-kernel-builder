# GKI 内核一键编译（Droidspaces + KernelSU）

给 Android 手机编译带 **Droidspaces 容器支持** 和 **内置 root** 的 GKI 内核。

- **云端编译**：编译在 GitHub 的服务器上跑，你电脑只负责点选，不需要装 Linux
- **本地编译**：如果你电脑有 WSL / Ubuntu，也可以在本机编译

原始脚本来自 [404-GCross/Droidspaces_GKI_Buildin_Local](https://github.com/404-GCross/Droidspaces_GKI_Buildin_Local)，
本仓库做了非交互式改造（原脚本是纯交互菜单，无法自动化）。

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

拆成三段记下来：

| 输出里的 | 对应到工具里 |
|---|---|
| `android14` | Android 与内核大版本 → **Android 14 - 6.1** |
| `6.1` | （同上，一起选） |
| `138` | 子版本号 → 填 **138** |

---

## 一、三步开始（Windows，推荐云端）

### 第 1 步：把本仓库 Fork 到你自己的 GitHub 账号

点本页右上角 **Fork** 按钮。

> 为什么必须 Fork：编译是在 GitHub Actions 上跑的，得用**你自己账号下**的仓库，否则没有权限启动任务。

### 第 2 步：安装并登录 gh

1. 下载安装：https://cli.github.com
2. 打开 PowerShell 或 cmd，执行：
   ```
   gh auth login
   ```
   一路回车，用浏览器登录即可

### 第 3 步：双击运行

下载这两个文件到**同一个文件夹**：

- `启动编译.bat`
- `build-gki.ps1`

双击 `启动编译.bat`，按菜单提示选版本就行。

> 脚本会自动读取你 gh 登录的用户名，拼出 `你的用户名/gki-kernel-builder`，
> **前提是你 Fork 时没改仓库名**。改了的话，在主菜单选 `5` 手动填一下。

---

## 二、用 Linux / WSL 的朋友

不用 Fork，不用 gh，直接一条命令：

```bash
curl -sL -o gkibuild.sh https://raw.githubusercontent.com/<你的用户名>/gki-kernel-builder/main/gkibuild.sh
chmod +x gkibuild.sh
./gkibuild.sh
```

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

**Q：编译要多久？**
云端约 45-60 分钟。跑完在 Actions 页面底部 Artifacts 下载。

**Q：免费额度够吗？**
GitHub 免费账号每月 2000 分钟 Actions 时长，一次编译约 50 分钟，一个月能编 40 次左右。

---

## 七、文件说明

| 文件 | 用途 |
|---|---|
| `启动编译.bat` | Windows 双击入口（纯英文，规避中文 bat 的编码坑） |
| `build-gki.ps1` | Windows 端菜单程序，负责选版本 + 调 gh/wsl |
| `gkibuild.sh` | Linux / WSL 端一键脚本（向导 + 命令行两种模式） |
| `.github/workflows/build-gki.yml` | 云端编译工作流 |

脚本部分遵循 GPL v2，版权归原作者 404-GCross。内核源码、KernelSU 等组件各自遵循其原始许可证。
