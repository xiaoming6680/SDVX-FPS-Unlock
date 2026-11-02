# SDVX FPS Unlock

解除 SOUND VOLTEX（KFC）在 spice2x 下的 120 帧内部限帧，可选 144 / 165 / 180 / 185 / 240 / 300 FPS。

只修改 spice2x 的补丁列表，补丁在游戏运行时写入内存，不改动任何游戏文件。本仓库不包含任何游戏文件。

> 实验性：游戏部分逻辑按 120 帧写死，个别动画可能变快。打歌感觉不对就改回 120。

![原理示意](docs/images/how-it-works.svg)

## 安装

1. 关闭游戏。
2. 从 [Releases](https://github.com/xiaoming6680/SDVX-FPS-Unlock/releases/latest) 下载 `SDVX-FPS-Unlock-*.zip`，解压后放进游戏根目录（含 `contents` 的那一层），双击 `install.bat`。
   放在别处也可以，脚本找不到游戏时会让你输入路径。
3. 启动游戏，按 F4 → Patches，把下面三项选成**同一个数**（等于屏幕刷新率最好），点 Save，重启游戏：
   - Game FPS Target
   - Note FPS Target
   - Frame Limiter Target (Experimental)

   ![F4 → Patches 中三项都选 180 FPS](docs/images/patches.png)

4. **竖屏显示器（1080×1920）必做**：F4 → Options → Display → Monitor → **Monitor Refresh Rate** 填同一个数，重启游戏。
   不设的话游戏会把屏幕切到 120Hz 并开垂直同步，帧数仍是 120。横屏显示器不用设。

   ![Options → Display → Monitor Refresh Rate 填 180](docs/images/monitor-refresh-rate.png)

脚本会自动识别游戏版本、核对补丁位置；任何一处对不上都会取消，不改文件。更新游戏版本后要重新运行一次。

## 帧数还是 120？

- 竖屏显示器没有做安装第 4 步（Options → Display → Monitor Refresh Rate）。
- 选完补丁后没有完全重启游戏。
- 显卡驱动强制开了垂直同步：NVIDIA 控制面板里改回「使用 3D 应用程序设置」。

## 已测试

| 游戏版本 | 显示器 | 结果 |
|---|---|---|
| KFC:J:G:A:2026101300 | 2560×1600 300Hz | 300 FPS 正常 |
| KFC:J:G:A:2026071400 | 1080×1920 180Hz | 180 FPS 正常（Monitor Refresh Rate 设为 180） |

## 恢复

F4 → Patches 里三项都选回 120 FPS。彻底还原：把 `contents\patches\` 下的 `*.before-fps-unlock.bak` 改名覆盖回同名 `.json`。

## 原理

见 [docs/逆向记录.md](docs/逆向记录.md)。

## License

[MIT](LICENSE)
