SDVX FPS Unlock
https://github.com/xiaoming6680/SDVX-FPS-Unlock

==================================== 中文 ====================================

解除 SOUND VOLTEX（KFC）在 spice2x 下的 120 帧内部限帧，可选 144 / 165 / 180 / 185 / 240 / 300 FPS。
补丁只在游戏运行时写入内存，不修改任何游戏文件。实验性：个别动画可能变快，感觉不对就改回 120。

安装
1. 关闭游戏。
2. 把本文件夹放进游戏根目录（含 contents 的那一层），双击 install.bat。
3. 启动游戏 -> F4 -> Patches，把下面三项选成同一个数（等于屏幕刷新率最好），点 Save，重启游戏：
     Game FPS Target / Note FPS Target / Frame Limiter Target (Experimental)
4. 竖屏显示器（1080x1920）还要设：F4 -> Options -> Display -> Monitor -> Monitor Refresh Rate 填同一个数，重启游戏。

卸载：三项都选回 120 FPS。还原补丁文件：把 contents\patches\*.before-fps-unlock.bak 改名覆盖回同名 .json。
常见问题和原理见项目主页。

免责声明：本项目与 KONAMI 无关，不包含任何游戏文件；仅供个人学习研究，请勿用于官方联网服务；
按「原样」提供，不附带任何担保，使用后果自负。

=================================== English ==================================

Lifts the internal 120 FPS cap of SOUND VOLTEX (KFC) on spice2x: 144 / 165 / 180 / 185 / 240 / 300 FPS.
Patches are applied in memory at launch; no game files are modified. Experimental: some animations
may run faster. Switch back to 120 if gameplay feels off.

Install
1. Close the game.
2. Put this folder in the game folder (the one containing "contents") and run install.bat.
3. Start the game -> F4 -> Patches, set these three to the same value (ideally your refresh rate),
   click Save and restart:
     Game FPS Target / Note FPS Target / Frame Limiter Target (Experimental)
4. Portrait monitors (1080x1920): also set F4 -> Options -> Display -> Monitor -> Monitor Refresh Rate
   to the same value and restart.

Uninstall: set all three back to 120 FPS. To restore the patch file, rename
contents\patches\*.before-fps-unlock.bak back to the matching .json.
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
