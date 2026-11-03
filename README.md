<div align="center">

# SDVX FPS Unlock

**解除 SOUND VOLTEX 在 spice2x 下的 120 帧内部限帧 — 任意目标帧数（60–1000 FPS）**

[![Release](https://img.shields.io/github/v/release/xiaoming6680/SDVX-FPS-Unlock?style=flat-square)](https://github.com/xiaoming6680/SDVX-FPS-Unlock/releases/latest) [![License](https://img.shields.io/github/license/xiaoming6680/SDVX-FPS-Unlock?style=flat-square)](LICENSE) ![Platform](https://img.shields.io/badge/platform-Windows-0078D6?style=flat-square) ![Loader](https://img.shields.io/badge/loader-spice2x-B5193F?style=flat-square)

**简体中文** · [English](README.en.md)

</div>

> [!WARNING]
> **实验性功能。** 游戏部分逻辑按 120 帧写死，个别动画可能变快。打歌感觉不对就改回 120。

> [!IMPORTANT]
> **目标帧数尽量填显示器支持的刷新率**（安装器会列出来）。和显示器不符时画面会不顺滑或撕裂；竖屏显示器上 Live2D 角色动画还会变快或变慢。

<p align="center">
  <img src="docs/images/how-it-works.svg" alt="原理示意" width="760">
</p>

## 目录

- [功能](#功能)
- [运行要求](#运行要求)
- [快速开始](#快速开始)
- [已测试版本](#已测试版本)
- [常见问题](#常见问题)
- [卸载](#卸载)
- [原理](#原理)
- [免责声明](#免责声明)
- [致谢](#致谢)
- [许可证](#许可证)

## 功能

- **解除真正的上限**：修改游戏内部的限帧器，而不只是改报告给游戏的刷新率。
- **任意帧数**：安装时输入目标帧数（默认取显示器最高刷新率），不限于预设档位；填了显示器不支持的数会提醒。
- **一步装好**：自动在 spice2x 里选中三个补丁；竖屏显示器同时设好 Monitor Refresh Rate。
- **速度同步**：*Game FPS Target*、*Note FPS Target* 与限帧器用同一个数，音符速度保持正确。
- **不改游戏文件**：全部通过 spice2x 补丁在启动时写入内存。
- **自动适配版本**：根据游戏 dll 找到对应补丁文件，逐字节核对，用特征码定位限帧器；任何一处对不上都会取消，不改文件。
- **可重复运行**：首次安装备份原补丁文件，再次运行结果相同。

## 运行要求

- Windows 10 / 11（使用系统自带的 Windows PowerShell 5.1）
- 用 **spice2x** 启动的 SOUND VOLTEX（`KFC`），补丁文件位于 `contents\patches\`

## 快速开始

1. **关闭游戏。**
2. 从 [Releases](https://github.com/xiaoming6680/SDVX-FPS-Unlock/releases/latest) 下载 `SDVX-FPS-Unlock-*.zip`，解压到游戏根目录（含 `contents` 的那一层），双击 **`install.bat`**。
   放在别处也可以，脚本找不到游戏时会让你输入路径。
3. 安装器会列出显示器和支持的刷新率，**输入目标帧数**后回车（直接回车用显示器最高刷新率）。
   **尽量填安装器列出的、显示器支持的刷新率，不要用和显示器不符的帧数。** 不符时画面会不顺滑或撕裂；竖屏显示器（1080×1920）是垂直同步定帧数，Live2D 角色动画却按这个数计时，对不上动画还会变快或变慢。填了不支持的数，安装器会提醒并让你确认。
4. 安装器会自动完成：
   - 生成三个补丁的档位（含你输入的数），并在 spice2x 里全部选中
   - 竖屏显示器：把 **Monitor Refresh Rate** 设成同一个数（否则游戏会切到 120Hz 并开垂直同步，帧数仍是 120）
5. 启动游戏，按 **F12** 看帧数。

想换帧数就重新运行 `install.bat`；更新游戏版本后也要重新运行一次。

<details>
<summary>安装器提示「需要手动选择」时</summary>

游戏还没用 spice2x 启动过时，安装器找不到它的设置文件。先启动一次游戏再运行安装器，或者手动设置：

1. **F4 → Patches**，把 Game FPS Target、Note FPS Target、Frame Limiter Target (Experimental) 选成同一个数，点 **Save**，重启游戏。

   ![F4 → Patches 中三项都选 180 FPS](docs/images/patches.png)

2. 仅竖屏：**F4 → Options → Display → Monitor → Monitor Refresh Rate** 填同一个数，重启游戏。

   ![Options → Display → Monitor Refresh Rate 填 180](docs/images/monitor-refresh-rate.png)

</details>

## 已测试版本

| 游戏版本 | 显示器 | 结果 |
|---|---|---|
| `KFC:J:G:A:2026101300` | 2560×1600 · 300Hz | ✅ 300 FPS |
| `KFC:J:G:A:2026071400` | 1080×1920 · 180Hz | ✅ 180 FPS（Monitor Refresh Rate 设为 180） |

在其他版本测试过？欢迎提交[版本测试报告](https://github.com/xiaoming6680/SDVX-FPS-Unlock/issues/new?template=1-compatibility.yml)。

## 常见问题

<details>
<summary><b>帧数还是 120</b></summary>

- 保存补丁后要完全重启游戏，限帧器只在启动时读取。
- 竖屏显示器：Monitor Refresh Rate 没设上，重新运行安装器，或按[快速开始](#快速开始)里的手动步骤设置。
- 显卡驱动强制开了垂直同步：NVIDIA 控制面板里改回「使用 3D 应用程序设置」。

</details>

<details>
<summary><b>游戏卡在待机视频不动</b></summary>

- 释放显存（关掉模型训练等占显卡的程序）。
- 退出网易 GameViewer 等虚拟显示器软件，多出来的显示器会干扰刷新率判断。
- 确认三个补丁和 Monitor Refresh Rate 用的是同一个数。

</details>

<details>
<summary><b>切到后台再切回来画面不刷新</b></summary>

打开 **F4 → Options → Windowed**（窗口模式），并保持 SDVX 副屏重绘（subscreen redraw）开启。

</details>

<details>
<summary><b>动画或音符变快</b></summary>

- 先确认三个补丁选的是同一个数（安装器会自动选好，之后在 F4 里改过就可能不一致）。
- 目标帧数是不是显示器支持的刷新率；不是的话重新运行安装器，输入列出的刷新率之一。
- 竖屏显示器：Monitor Refresh Rate 也要是这个数，且等于显示器实际刷新率。比如屏幕 180Hz，就输入 180，不要输入 300。
- 仍然不对：游戏部分逻辑按 120 帧写死，把三个补丁都改回 120 FPS。

</details>

## 卸载

重新运行安装器输入 120，或在 F4 → Patches 里三项都选回 **120 FPS**。竖屏显示器把 Monitor Refresh Rate 改回原来的值。
要完全还原，把安装器备份的 `*.before-fps-unlock.bak` 改名覆盖回原文件：`contents\patches\` 里的补丁文件，以及 spice2x 的补丁设置和 `spicetools.xml`（安装时会显示路径）。

## 原理

游戏用一个内部限帧器控制帧率，初始化为 120000 mHz（`mov ebx, 120000`）。安装脚本用特征码找到这条指令，加入替换这个常量的补丁；同时扩展原有两个 FPS 补丁，让游戏按同一速率计算音符和画面时间。

完整逆向记录：[docs/逆向记录.md](docs/逆向记录.md)

## 免责声明

- 本项目与 **KONAMI 没有任何关联**，未获其认可或授权。SOUND VOLTEX、e-amusement 等名称是其各自所有者的商标。
- 本仓库**不包含任何游戏文件、可执行程序或素材**，也不说明如何获取。
- 仅供**个人学习、研究与互操作性测试**，用于你依法有权使用的软件。使用者须自行遵守所在地法律及相关条款。
- **请勿用于官方联网服务**或任何竞技、排名环境。
- 本软件**按原样提供，不附带任何担保**。作者不对使用本软件造成的任何损害、数据丢失、账号处理或其他后果负责。
- 权利人如有疑虑，请[提交 issue](https://github.com/xiaoming6680/SDVX-FPS-Unlock/issues/new?template=4-other.yml)，会尽快处理。

## 致谢

- [spice2x](https://spice2x.github.io/)：本项目依赖的启动器和补丁管理器
- 原版 *Game FPS Target* / *Note FPS Target* 补丁的社区作者们

## 许可证

[MIT](LICENSE)
