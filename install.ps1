param([string]$GameDir, [int]$Fps = 0, [switch]$Yes)

$ErrorActionPreference = 'Stop'
$Presets = 60, 120, 144, 165, 180, 185, 240, 300
$MinFps = 60
$MaxFps = 1000
$LimiterName = 'Frame Limiter Target (Experimental)'
# mov ebx, 120000 ; mov edx, ebx ; mov rcx, rax ; call -- sets the game's internal frame limiter (mHz)
$LimiterSig = 'BBC0D401008BD3488BC8E8'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Latin1 = [Text.Encoding]::GetEncoding(28591)
$Utf8 = New-Object Text.UTF8Encoding $false

function Say([string]$zh, [string]$en, [string]$color = 'Gray') {
    Write-Host $zh -ForegroundColor $color
    Write-Host "  $en" -ForegroundColor DarkGray
}

function Fail([string]$zh, [string]$en, [int]$code) {
    Say $zh $en 'Red'
    Say '没有修改任何文件。' 'No files were changed.'
    exit $code
}

function Find-Contents([string]$dir) {
    if (-not $dir) { return $null }
    foreach ($c in @($dir, (Join-Path $dir 'contents'), (Join-Path $dir 'LAZY_KFC\contents'))) {
        if (Test-Path -LiteralPath (Join-Path $c 'modules\soundvoltex.dll')) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

function Hex([byte[]]$b) { ($b | ForEach-Object { $_.ToString('X2') }) -join '' }
function Bytes([string]$hex) { [byte[]]($hex -split '(..)' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) }) }
function Slice([byte[]]$b, [int]$off, [int]$len) { [byte[]]$b[$off..($off + $len - 1)] }
function Le32([int]$v) { Hex ([BitConverter]::GetBytes([int32]$v)) }
function Sha256([string]$s) { Hex ((New-Object Security.Cryptography.SHA256Managed).ComputeHash($Utf8.GetBytes($s))) }

function New-Option([string]$name, [int]$offset, [string]$data) {
    [pscustomobject]@{ name = $name; patch = [pscustomobject]@{ offset = $offset; dllName = 'soundvoltex.dll'; data = $data } }
}

function Backup([string]$path) {
    $bak = "$path.before-fps-unlock.bak"
    if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $path -Destination $bak }
}

# keep the file's own BOM so spice reads it the same way as before
function Write-Text([string]$path, [string]$text) {
    $raw = [IO.File]::ReadAllBytes($path)
    $bom = $raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $bom))
}

if (-not ('SdvxDisplays' -as [type])) { Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class SdvxDisplays {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplayDevices(string dev, int i, ref DISPLAY_DEVICE dd, int flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
    public class Info { public string Name; public bool Primary; public int Width, Height, Hz; public int[] Rates; }
    public static List<Info> Get() {
        var list = new List<Info>();
        var dd = new DISPLAY_DEVICE(); dd.cb = Marshal.SizeOf(dd);
        for (int i = 0; EnumDisplayDevices(null, i, ref dd, 0); i++, dd.cb = Marshal.SizeOf(dd)) {
            if ((dd.StateFlags & 1) == 0) continue;  // not attached to the desktop
            var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(dm);
            if (!EnumDisplaySettings(dd.DeviceName, -1, ref dm)) continue;  // ENUM_CURRENT_SETTINGS
            var info = new Info { Name = dd.DeviceName, Primary = (dd.StateFlags & 4) != 0, Width = dm.dmPelsWidth, Height = dm.dmPelsHeight, Hz = dm.dmDisplayFrequency };
            var rates = new SortedSet<int>();
            var m = new DEVMODE(); m.dmSize = (short)Marshal.SizeOf(m);
            for (int k = 0; EnumDisplaySettings(dd.DeviceName, k, ref m); k++) {
                bool same = (m.dmPelsWidth == info.Width && m.dmPelsHeight == info.Height) || (m.dmPelsWidth == info.Height && m.dmPelsHeight == info.Width);
                if (same && m.dmDisplayFrequency > 1) rates.Add(m.dmDisplayFrequency);
            }
            if (info.Hz > 1) rates.Add(info.Hz);
            info.Rates = new int[rates.Count]; rates.CopyTo(info.Rates);
            list.Add(info);
        }
        return list;
    }
}
'@ }

Write-Host '=== SDVX FPS Unlock ===' -ForegroundColor Cyan

$contents = Find-Contents $GameDir
if (-not $contents) { $contents = Find-Contents (Split-Path -Parent $Here) }
if (-not $contents) { $contents = Find-Contents $Here }
while (-not $contents) {
    if ($Yes) { Fail '没找到游戏，请用 -GameDir 指定游戏文件夹。' 'Game not found; pass the game folder with -GameDir.' 1 }
    $in = Read-Host '没找到游戏，请输入游戏文件夹路径 / Game not found, enter the game folder path (Enter to quit)'
    if (-not $in) { exit 1 }
    $contents = Find-Contents $in.Trim('"')
    if (-not $contents) { Say '这个文件夹里没有 contents\modules\soundvoltex.dll' 'contents\modules\soundvoltex.dll not found in this folder' 'Yellow' }
}
Say "游戏目录: $contents" "Game folder: $contents"

if (Get-Process -Name spice64 -ErrorAction SilentlyContinue) { Fail '游戏正在运行，请先关闭游戏再安装。' 'The game is running. Close it first.' 3 }

# --- identify the game version from the PE header, the same way spice names its patch files
$dll = [IO.File]::ReadAllBytes((Join-Path $contents 'modules\soundvoltex.dll'))
$pe = [BitConverter]::ToInt32($dll, 0x3C)
$stamp = [BitConverter]::ToUInt32($dll, $pe + 8)
$entry = [BitConverter]::ToUInt32($dll, $pe + 24 + 16)
$patchId = 'KFC-{0:x8}_{1:x}' -f $stamp, $entry
$patchFile = Join-Path $contents "patches\$patchId.json"
if (-not (Test-Path -LiteralPath $patchFile)) {
    Fail "找不到这个游戏版本的补丁文件: $patchFile" "No spice2x patch file for this game version: $patchFile" 2
}
Say "补丁文件: $patchFile" "Patch file: $patchFile"

$json = [IO.File]::ReadAllText($patchFile)
# Windows PowerShell 5.1 emits a top-level JSON array as a single object; pipe it to unroll
$patches = @((ConvertFrom-Json $json) | ForEach-Object { $_ })
$game = $patches | Where-Object { $_.name -eq 'Game FPS Target' } | Select-Object -First 1
$note = $patches | Where-Object { $_.name -eq 'Note FPS Target' } | Select-Object -First 1
if (-not $game -or -not $note) { Fail '补丁文件里没有 Game FPS Target / Note FPS Target。' 'Game FPS Target / Note FPS Target not found in the patch file.' 4 }

# --- check every location before asking anything, so an unsupported version stops early
$g60 = $game.patches | Where-Object { $_.name -like '60 FPS*' } | Select-Object -First 1
if (-not $g60) { Fail 'Game FPS Target 里没有 60 FPS 选项。' 'Game FPS Target has no 60 FPS option.' 4 }
$gOff = [int]$g60.patch.offset
if ($g60.patch.data.Length -eq 4) { $gOff += 1 }  # already widened by an earlier install
if ((Hex (Slice $dll ($gOff - 6) 8)) -ne '0000000000004E40') { Fail 'Game FPS Target 的位置和游戏文件对不上。' 'Game FPS Target does not match the game file.' 5 }

$n60 = $note.patches | Where-Object { $_.name -like '60 FPS*' } | Select-Object -First 1
$n120 = $note.patches | Where-Object { $_.name -like '120 FPS*' } | Select-Object -First 1
if (-not $n60 -or -not $n120 -or $n120.patch.data -notmatch '^B878000000') { Fail 'Note FPS Target 的格式和预期不一样。' 'Note FPS Target has an unexpected format.' 4 }
$nOff = [int]$n60.patch.offset
if ((Hex (Slice $dll $nOff ($n60.patch.data.Length / 2))) -ne $n60.patch.data.ToUpper()) { Fail 'Note FPS Target 的位置和游戏文件对不上。' 'Note FPS Target does not match the game file.' 5 }

# internal frame limiter: find the instruction by signature, it must be unique
$text = $Latin1.GetString($dll)
$sig = $Latin1.GetString((Bytes $LimiterSig))
$hits = @(); $i = $text.IndexOf($sig, [StringComparison]::Ordinal)
while ($i -ge 0) { $hits += $i; $i = $text.IndexOf($sig, $i + 1, [StringComparison]::Ordinal) }
if ($hits.Count -ne 1) { Fail "找到 $($hits.Count) 处限帧器特征码（需要正好 1 处），这个版本不支持。" "Found $($hits.Count) frame limiter signatures (exactly 1 required); this version is not supported." 6 }
$lOff = $hits[0]

# --- spice2x settings: the last launch's arguments in log.txt tell where the launcher keeps them
$logArgs = ''
$logFile = Join-Path $contents 'log.txt'
if (Test-Path -LiteralPath $logFile) { $logArgs = (Get-Content -LiteralPath $logFile -TotalCount 60 -Encoding UTF8) -join "`n" }
function Find-Config([string]$flag, [string]$file) {
    $m = [regex]::Match($logArgs, "(?m)^\s*-$flag\s+(.+?)\s*$")
    $cands = @()
    if ($m.Success) { $p = $m.Groups[1].Value.Trim('"'); $cands += $(if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $contents $p }) }
    $cands += (Join-Path $contents $file), (Join-Path $env:APPDATA "spice2x\$file"), (Join-Path $env:APPDATA $file)
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return (Resolve-Path -LiteralPath $c).Path } }
    return $null
}
$spiceXml = Find-Config 'cfgpath' 'spicetools.xml'
$managerFile = Find-Config 'patchcfgpath' 'spicetools_patch_manager.json'

$xmlText = $null; $sdvxBlock = $null
if ($spiceXml) {
    $xmlText = [IO.File]::ReadAllText($spiceXml)
    $sdvxBlock = [regex]::Match($xmlText, '(?s)<game name="Sound Voltex">.*?</game>')
    if (-not $sdvxBlock.Success) { $sdvxBlock = $null }
}

# --- monitor detection
$displays = @([SdvxDisplays]::Get())
$mainName = $null
if ($sdvxBlock) {
    $m = [regex]::Match($sdvxBlock.Value, '<option name="mainmonitor" value="([^"]*)"')
    if ($m.Success -and $m.Groups[1].Value) { $mainName = $m.Groups[1].Value }
}
$main = $displays | Where-Object { $mainName -and $_.Name -eq $mainName } | Select-Object -First 1
if (-not $main) { $main = $displays | Where-Object { $_.Primary } | Select-Object -First 1 }
if (-not $main) { $main = $displays | Select-Object -First 1 }
Write-Host ''
foreach ($d in $displays) {
    $tag = if ($d -eq $main) { '  <- 游戏显示器 / game monitor' } else { '' }
    Write-Host ("  {0}  {1}x{2}  {3} Hz  ({4} Hz){5}" -f $d.Name, $d.Width, $d.Height, $d.Hz, ($d.Rates -join '/'), $tag)
}
$portrait = $main -and $main.Height -gt $main.Width
$maxHz = if ($main) { ($main.Rates | Measure-Object -Maximum).Maximum } else { 0 }

# --- target frame rate
$suggest = if ($maxHz) { [Math]::Min($MaxFps, [Math]::Max($MinFps, [int]$maxHz)) } else { 120 }
while ($Fps -lt $MinFps -or $Fps -gt $MaxFps) {
    if ($Yes -and $Fps -eq 0) { $Fps = $suggest; break }
    if ($Yes) { Fail "帧数需要在 $MinFps 到 $MaxFps 之间。" "The frame rate must be between $MinFps and $MaxFps." 7 }
    Write-Host ''
    if ($main) {
        Say "建议填显示器支持的刷新率: $($main.Rates -join ' / ') Hz。尽量不要用和显示器不符的帧数。" "Use a refresh rate your monitor supports: $($main.Rates -join ' / ') Hz. Avoid frame rates that do not match the monitor." 'Cyan'
    }
    $in = Read-Host "输入目标帧数 / Target FPS ($MinFps-$MaxFps, Enter = $suggest)"
    if (-not $in) { $Fps = $suggest; break }
    $n = 0
    if (-not [int]::TryParse($in.Trim(), [ref]$n) -or $n -lt $MinFps -or $n -gt $MaxFps) {
        Say "请输入 $MinFps 到 $MaxFps 之间的整数。" "Enter a whole number between $MinFps and $MaxFps." 'Yellow'
        continue
    }
    $Fps = $n
}
Say "目标帧数: $Fps" "Target FPS: $Fps" 'Cyan'

$supported = $main -and ($main.Rates -contains $Fps)
if ($main -and -not $supported) {
    Say "$Fps 和游戏显示器的刷新率不符（支持 $($main.Rates -join ' / ') Hz），建议改用其中一个。" "$Fps does not match the game monitor's refresh rates ($($main.Rates -join ' / ') Hz); using one of them is recommended." 'Yellow'
    if ($portrait) {
        # portrait runs with V-Sync: frames follow the monitor, Live2D timing follows the limiter
        Say '竖屏是垂直同步定帧数，实际帧数会和设定不一致，Live2D 角色动画会变快或变慢。' 'Portrait mode uses V-Sync, so the real frame rate will differ and Live2D animations will run too fast or slow.' 'Yellow'
    } else {
        Say '帧数和刷新率对不上时画面会不顺滑或撕裂。' 'A frame rate that does not match the refresh rate stutters or tears.' 'Yellow'
        if ($Fps -gt $maxHz) { Say "显示器最高 $maxHz Hz，超出的帧也看不到。" "The monitor tops out at $maxHz Hz; extra frames are not shown." 'Yellow' }
    }
    if (-not $Yes) {
        $ok = Read-Host '仍然继续？/ Continue anyway? (y/N)'
        if ($ok -notmatch '^[yY]') { Fail '已取消，请重新运行并输入显示器支持的刷新率。' 'Cancelled. Run again and enter a refresh rate your monitor supports.' 8 }
    }
}

$Rates = @($Presets + $Fps | Sort-Object -Unique)

# --- Game FPS Target: a double constant (60.0); rewrite the top two bytes so every option covers the same range
$game.patches = @(foreach ($r in $Rates) {
    $b = [BitConverter]::GetBytes([double]$r)
    New-Option ("$r FPS" + $(if ($r -eq 60) { ' (Default)' } else { '' })) ($gOff - 1) (Hex (Slice $b 5 2))
})

# --- Note FPS Target: replace the refresh-rate read with mov eax, <rate>
$tail = $n120.patch.data.Substring(10)
$note.patches = @($n60) + @(foreach ($r in $Rates | Where-Object { $_ -ne 60 }) { New-Option "$r FPS" $nOff ('B8' + (Le32 $r) + $tail) })

$limiter = [pscustomobject]@{
    name = $LimiterName
    description = "Changes the game's internal frame limiter (120 FPS by default). Use the same value for Game FPS Target and Note FPS Target. Parts of the game may run faster than normal."
    gameCode = 'KFC'
    type = 'union'
    patches = @(foreach ($r in $Rates | Where-Object { $_ -ne 60 -or $Fps -eq 60 }) {
        New-Option ("$r FPS" + $(if ($r -eq 120) { ' (Default)' } else { '' })) $lOff ('BB' + (Le32 ($r * 1000)))
    })
}

$out = New-Object System.Collections.ArrayList
foreach ($p in $patches) {
    if ($p.name -eq $LimiterName) { continue }
    [void]$out.Add($p)
    if ($p.name -eq 'Note FPS Target') { [void]$out.Add($limiter) }
}

Write-Host ''
Backup $patchFile
[IO.File]::WriteAllText($patchFile, (ConvertTo-Json -InputObject $out.ToArray() -Depth 20), $Utf8)
Say '已写入补丁文件（原文件备份为 .before-fps-unlock.bak）。' 'Patch file updated (original backed up as .before-fps-unlock.bak).' 'Green'

# --- select the three patches in spice2x's patch manager
# spice identifies a patch by sha256(gameCode + patch file id + name + description)
$selected = $false
if ($managerFile) {
    $cfg = ConvertFrom-Json ([IO.File]::ReadAllText($managerFile))
    if (-not $cfg.union_patches_enabled) { $cfg | Add-Member -NotePropertyName union_patches_enabled -NotePropertyValue ([pscustomobject]@{}) -Force }
    foreach ($p in @($game, $note, $limiter)) {
        $opt = $p.patches | Where-Object { $_.name -match "^$Fps FPS( \(Default\))?$" } | Select-Object -First 1
        $hash = (Sha256 ("$($p.gameCode)$patchId$($p.name)$($p.description)")).ToLower()
        $cfg.union_patches_enabled | Add-Member -NotePropertyName $hash -NotePropertyValue $opt.name -Force
    }
    # auto apply makes spice apply the saved selection at every launch
    $ident = Join-Path $contents 'prop\ea3-ident.xml'
    if (Test-Path -LiteralPath $ident) {
        $soft = ([xml][IO.File]::ReadAllText($ident)).SelectSingleNode('/ea3_conf/soft')
        $gameIdent = (@('model', 'dest', 'spec', 'rev', 'ext') | ForEach-Object { $soft.SelectSingleNode($_).InnerText }) -join ':'
        $auto = @($cfg.auto_apply | Where-Object { $_ })
        if ($auto -notcontains $gameIdent) { $cfg | Add-Member -NotePropertyName auto_apply -NotePropertyValue @($auto + $gameIdent) -Force }
    }
    Backup $managerFile
    Write-Text $managerFile (ConvertTo-Json -InputObject $cfg -Depth 20)
    $selected = $true
    Say "已在 spice2x 中选中三项 $Fps FPS: $managerFile" "Selected $Fps FPS for all three patches in spice2x: $managerFile" 'Green'
} else {
    Say '没找到 spice2x 的补丁设置文件（游戏还没启动过？），需要手动选择。' 'spice2x patch settings not found (game never launched?); select the patches manually.' 'Yellow'
}

# --- Monitor Refresh Rate (-graphics-force-refresh): needed in portrait, kept in sync if already set
$refreshDone = $false
if ($sdvxBlock -and $supported) {
    $block = $sdvxBlock.Value
    $re = '<option name="graphics-force-refresh" value="([^"]*)"\s*/>'
    $m = [regex]::Match($block, $re)
    $newBlock = $null
    if ($m.Success -and ($portrait -or $m.Groups[1].Value)) {
        $newBlock = $block.Remove($m.Index, $m.Length).Insert($m.Index, "<option name=`"graphics-force-refresh`" value=`"$Fps`"/>")
    } elseif (-not $m.Success -and $portrait -and $block -match '</options>') {
        $newBlock = [regex]::Replace($block, '(\r?\n)(\s*)</options>', "`$1`$2    <option name=`"graphics-force-refresh`" value=`"$Fps`"/>`$1`$2</options>", 1)
    }
    if ($newBlock) {
        if ($newBlock -ne $block) {
            Backup $spiceXml
            Write-Text $spiceXml ($xmlText.Remove($sdvxBlock.Index, $sdvxBlock.Length).Insert($sdvxBlock.Index, $newBlock))
        }
        $refreshDone = $true
        Say "Monitor Refresh Rate 已设为 $Fps : $spiceXml" "Monitor Refresh Rate set to ${Fps}: $spiceXml" 'Green'
    }
}

Write-Host ''
Say '安装完成。' 'Done.' 'Green'
if ($selected) {
    Say "直接启动游戏即可，按 F12 看帧数。以后想换帧数，重新运行 install.bat。" 'Just start the game; press F12 to show FPS. Re-run install.bat to change the frame rate.'
} else {
    Say "接下来：启动游戏 -> F4 -> Patches，把下面三项都选成 $Fps FPS，点 Save，再重启游戏：" "Next: start the game -> F4 -> Patches, set these three to $Fps FPS, click Save and restart:"
    Write-Host '  Game FPS Target'
    Write-Host '  Note FPS Target'
    Write-Host "  $LimiterName"
}
if ($portrait -and -not $refreshDone) {
    Say "竖屏显示器还要设：F4 -> Options -> Display -> Monitor -> Monitor Refresh Rate 填 $Fps（必须是显示器支持的刷新率），再重启游戏。" "Portrait monitor: also set F4 -> Options -> Display -> Monitor -> Monitor Refresh Rate to $Fps (a rate your monitor supports) and restart."
}
