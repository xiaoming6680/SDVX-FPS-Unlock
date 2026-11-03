<div align="center">

# SDVX FPS Unlock

**Run SOUND VOLTEX above 120 FPS on spice2x**<br>
Works with any monitor: 144 / 165 / 180 / 240 / 300 Hz…

### [⬇ Download the latest version](https://github.com/xiaoming6680/SDVX-FPS-Unlock/releases/latest)

On that page, scroll to **Assets** and click `SDVX-FPS-Unlock-v….zip`

[简体中文](README.md) · **English**

</div>

## How to use

**1. Close the game and extract the zip into the game folder** (the one containing `contents`), then double-click **`install.bat`**

![Put the extracted folder in the game folder and double-click install.bat](docs/images/install-folder.png)

**2. Type your monitor's refresh rate and press Enter** (Enter alone = the highest refresh rate detected)

The installer selects the patches in spice2x for you and, on portrait monitors, sets Monitor Refresh Rate.

![The installer lists the monitor's refresh rates; entering 240 sets everything up](docs/images/installer.png)

If you enter a rate the monitor does not support, the installer warns you and lets you cancel and try again:

![Entering 175 triggers a mismatch warning; answering n cancels](docs/images/installer-warning.png)

**3. Start the game as usual**; turn on the FPS counter in the ESC menu

To change the frame rate, or after a game update, just run `install.bat` again.

> [!IMPORTANT]
> - **Enter a refresh rate your monitor supports** (the installer lists them; e.g. 144 for a 144 Hz monitor). A mismatch stutters, and on portrait monitors Live2D character animations also run too fast or slow.
> - Experimental: a few parts of the game are hard-coded for 120 FPS. If something feels off, run the installer again and enter 120.

## Having a problem?

Check the troubleshooting list below first. If that does not help, [file a bug](https://github.com/xiaoming6680/SDVX-FPS-Unlock/issues/new?template=2-bug.yml) and **always attach the log file `contents\log.txt`**: close the game after the problem happens and drag the file into the issue. Without the log we can hardly investigate.

![log.txt is in the contents folder of the game folder](docs/images/log-file.png)

## Troubleshooting

<details>
<summary><b>Still 120 FPS</b></summary>

- Fully restart the game after installing.
- Portrait monitor: if the installer says it will not set Monitor Refresh Rate, the monitor lacks that rate in the game's 1080×1920 fullscreen mode; pick one of the listed rates.
- V-Sync forced in the GPU driver: set it back to *Use the 3D application setting* in the NVIDIA Control Panel.

</details>

<details>
<summary><b>The game does not start after changing the frame rate</b></summary>

Run `install.bat` again and enter 120 (or set Monitor Refresh Rate back to 120 in your launcher / F4) and the game starts again. Then please [file a bug](https://github.com/xiaoming6680/SDVX-FPS-Unlock/issues/new?template=2-bug.yml) with `contents\log.txt` from the failed launch.

</details>

<details>
<summary><b>Animations or notes too fast</b></summary>

- The value must match your monitor's refresh rate; run the installer again to change it.
- If you changed patches in F4 → Patches afterwards, all three must use the same value.
- Still wrong: enter 120.

</details>

<details>
<summary><b>The installer says to select the patches manually</b></summary>

The game has not been launched with spice2x yet. Launch it once and re-run the installer, or set it up by hand: in **F4 → Patches** set Game FPS Target, Note FPS Target and Frame Limiter Target (Experimental) to the same value, click **Save** and restart. Portrait monitors also need **F4 → Options → Display → Monitor → Monitor Refresh Rate** set to that value.

![F4 → Patches with all three set to 180 FPS](docs/images/patches.png)

</details>

<details>
<summary><b>Game freezes on the attract video</b></summary>

- Free up GPU memory (close GPU-heavy apps).
- Quit virtual display software such as NetEase GameViewer.

</details>

<details>
<summary><b>Screen stops updating after Alt-Tab</b></summary>

Enable **F4 → Options → Windowed** and keep the SDVX subscreen redraw option on.

</details>

<details>
<summary><b>How to uninstall</b></summary>

Run `install.bat` again and enter 120. To restore everything, rename the installer's `*.before-fps-unlock.bak` backups back over the originals (paths are shown during install).

</details>

## Tested

| Game version | Monitor | Result |
|---|---|---|
| `KFC:J:G:A:2026101300` | 2560×1600 · 300 Hz | ✅ 300 FPS |
| `KFC:J:G:A:2026071400` | 1080×1920 · 180 Hz | ✅ 180 FPS |

Tested another version? Please submit a [version test report](https://github.com/xiaoming6680/SDVX-FPS-Unlock/issues/new?template=1-compatibility.yml). How it works (Chinese): [docs/逆向记录.md](docs/逆向记录.md).

## Disclaimer

Not affiliated with KONAMI. Contains no game files. For personal, educational use only; do not use with official online services. Provided "as is", without warranty; use at your own risk. Rights holders with concerns may [open an issue](https://github.com/xiaoming6680/SDVX-FPS-Unlock/issues/new?template=4-other.yml).

Thanks to [spice2x](https://spice2x.github.io/) and the community authors of the original FPS patches. License: [MIT](LICENSE)
