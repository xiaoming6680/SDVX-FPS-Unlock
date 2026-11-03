SDVX FPS Unlock
https://github.com/xiaoming6680/SDVX-FPS-Unlock

==================================== 中文 ====================================

解除 SOUND VOLTEX（KFC）在 spice2x 下的 120 帧内部限帧，目标帧数可任意填写（60-1000）。
补丁只在游戏运行时写入内存，不修改任何游戏文件。实验性：个别动画可能变快，感觉不对就改回 120。

安装
1. 关闭游戏。
2. 把本文件夹放进游戏根目录（含 contents 的那一层），双击 install.bat。
3. 输入目标帧数后回车（直接回车用显示器最高刷新率）。
   尽量填安装器列出的、显示器支持的刷新率，不要用和显示器不符的帧数：不符时画面会不顺滑或撕裂，
   竖屏显示器上 Live2D 角色动画还会变快或变慢。
4. 安装器会自动在 spice2x 里选好三个补丁，竖屏显示器同时设好 Monitor Refresh Rate。直接启动游戏即可。
   想换帧数就重新运行 install.bat。

卸载：重新运行 install.bat 输入 120。完全还原：把安装器备份的 *.before-fps-unlock.bak 改名覆盖回原文件。
常见问题和原理见项目主页。

免责声明：本项目与 KONAMI 无关，不包含任何游戏文件；仅供个人学习研究，请勿用于官方联网服务；
按「原样」提供，不附带任何担保，使用后果自负。

=================================== English ==================================

Lifts the internal 120 FPS cap of SOUND VOLTEX (KFC) on spice2x: any target frame rate (60-1000).
Patches are applied in memory at launch; no game files are modified. Experimental: some animations
may run faster. Switch back to 120 if gameplay feels off.

Install
1. Close the game.
2. Put this folder in the game folder (the one containing "contents") and run install.bat.
3. Type a target FPS and press Enter (Enter alone uses the monitor's highest refresh rate).
   Pick one of the refresh rates the installer lists; avoid frame rates that do not match your
   monitor. A mismatch stutters or tears, and on portrait monitors Live2D animations also run
   too fast or slow.
4. The installer selects all three patches in spice2x and, on portrait monitors, sets
   Monitor Refresh Rate. Just start the game. Re-run install.bat to change the frame rate.

Uninstall: re-run install.bat and enter 120. To restore everything, rename the installer's
*.before-fps-unlock.bak backups back over the originals.
See the project page for troubleshooting and details.

Disclaimer: not affiliated with KONAMI; contains no game files; for personal, educational use only;
do not use with official online services. Provided "as is", without warranty. Use at your own risk.

=================================== License ==================================

MIT License

Copyright (c) 2026 SDVX-FPS-Unlock contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
