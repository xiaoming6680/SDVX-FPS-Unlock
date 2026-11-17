param([string]$GameDir, [int]$Fps = 0, [switch]$Yes, [switch]$Restore)

$ErrorActionPreference = 'Stop'
$Presets = 60, 120, 144, 165, 180, 185, 240, 300
$MinFps = 60
$MaxFps = 1000
# spice remembers a selection by a hash that includes name and description: changing either loses it
$LimiterName = 'Frame Limiter Target (Experimental)'
$LimiterDesc = "Changes the game's internal frame limiter (120 FPS by default). Use the same value for Game FPS Target and Note FPS Target. Parts of the game may run faster than normal."
# mov ebx, 120000 ; mov edx, ebx ; mov rcx, rax ; call -- sets the game's internal frame limiter (mHz)
$LimiterSig = 'BBC0D401008BD3488BC8E8'
$KnobFixName = 'Knob Fix for High FPS'
$KnobDesc = 'Makes slow knob turns register in menus above 120 FPS. Works best with refresh rates multiple of 120: knobs might not be speed consistent otherwise because of input sampling variation.'
# earlier descriptions: their on/off hashes are removed on install and restore. Changing $KnobDesc? Move the old text here.
$KnobDescOld = @(
    'Makes slow knob turns register in menus (music select, level select, card registration) above 120 FPS. The game scales small knob movements by frame time; this removes the scaling.'  # v1.3.0
)
# menu knob filter: lea eax,[r9+r9*4] ; add eax,eax ; movd xmm1,eax ; cvtdq2pd xmm1,xmm1 ; mulsd xmm1,xmm2 ; addsd xmm1,[rdi+18h]
$KnobSig = '438D048903C0660F6EC8F30FE6C9F20F59CAF20F584F18'
# instruction spans of the knob fix (docs/逆向记录.md, "菜单旋钮"): the first one makes the filter sample on a 120 Hz
# clock, its fallback (the mulsd above -> nop) only drops the frame-time gain. fpsOffset = where the frame rate goes.
$KnobSpecs = @'
[
  {
    "name": "Sample accumulated knob positions on a 120 Hz clock",
    "anchor": "438D048903C0660F6EC8F30FE6C9F20F59CAF20F584F18",
    "offset": -155,
    "expected": "48B8DB34B6D782DE1B4349F7E848C1FA12488BC248C1E83F4803D0807F2800750848895720C64728010F57D2488BC2482B4720807F280048895720F2480F2AD0F20F5915????????7504C6472801",
    "enabled": "498D4001B97800000048F7E1B900CA9A3B48F7F1807F2800750F488947208937897704C6472801EB184889C2482B57207E0F48894720660FEFD2F2480F2AD2EB0D31C0E98D010000909090909090",
    "fallback": {
      "offset": 14,
      "expected": "F20F59CA",
      "enabled": "0F1F4000"
    },
    "guards": [
      {
        "offset": -77,
        "expected": "8B070F57F689470489372BF0"
      },
      {
        "offset": 314,
        "expected": "488B5C2440488B7424480F287424204883C4305FC3"
      }
    ]
  },
  {
    "name": "Keep the menu threshold independent of Game FPS Target",
    "anchor": "438D048903C0660F6EC8F30FE6C9F20F59CAF20F584F18",
    "offset": 61,
    "expected": "F20F101D????????",
    "enabled": "31C0B03CF20F2AD8"
  },
  {
    "name": "Keep the main menu idle timeout at one second",
    "anchor": "448BC09933C23BC2750EFF07833F787C098977FC8BCEEB0589378B4FFC",
    "offset": 0,
    "expected": "448BC09933C23BC2750EFF07833F787C098977FC8BCEEB0589378B4FFC",
    "enabled": "4189C085C0750EFF07813FE00100007C0689F1EB0589378B4FFC909090",
    "fpsOffset": 11
  },
  {
    "name": "Keep the registration left knob idle timeout at one second",
    "anchor": "448BC09933C233FF3BC2750DFF4644837E44787C078BCFEB06897E448B4E40",
    "offset": 0,
    "expected": "448BC09933C233FF3BC2750DFF4644837E44787C078BCFEB06897E448B4E40",
    "enabled": "4189C031FF85C07510FF4644817E44E00100007C0789F9EB06897E448B4E40",
    "fpsOffset": 15
  },
  {
    "name": "Keep the registration right knob idle timeout at one second",
    "anchor": "448BC09933C23BC27513FF868C00000083BE8C000000787C0A8BCFEB0C89BE8C0000008B8E88000000",
    "offset": 0,
    "expected": "448BC09933C23BC27513FF868C00000083BE8C000000787C0A8BCFEB0C89BE8C0000008B8E88000000",
    "enabled": "4189C085C07516FF868C00000081BE8C000000E00100007C0A89F9EB0C89BE8C0000008B8E88000000",
    "fpsOffset": 19
  }
]
'@
$BakSuffix = '.before-fps-unlock.bak'
$SdvxBlockRe = '(?s)<game name="Sound Voltex">.*?</game>'
$RefreshRe = '<option name="graphics-force-refresh" value="([^"]*)"\s*/>'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Latin1 = [Text.Encoding]::GetEncoding(28591)
$Utf8 = New-Object Text.UTF8Encoding $false

try { $Host.UI.RawUI.WindowTitle = 'SDVX FPS Unlock' } catch {}
$IsZh = (Get-UICulture).Name -like 'zh*' -or (Get-Culture).Name -like 'zh*'
function T([string]$zh, [string]$en) { if ($IsZh) { $zh } else { $en } }

function Say([string]$zh, [string]$en, [string]$color = 'Gray') { Write-Host "     $(T $zh $en)" -ForegroundColor $color }
function Mark([string]$mark, [string]$color, [string]$zh, [string]$en) {
    Write-Host "  $mark  " -ForegroundColor $color -NoNewline
    Write-Host (T $zh $en)
}
function Ok([string]$zh, [string]$en) { Mark '√' Green $zh $en }
function Warn([string]$zh, [string]$en) { Mark '!' Yellow $zh $en }
function Item([string]$label, [string]$value, [string]$color = 'White') {
    Write-Host ('     {0}' -f $label) -ForegroundColor DarkGray -NoNewline
    Write-Host "  $value" -ForegroundColor $color
}
function Step([int]$n, [string]$zh, [string]$en) {
    Write-Host ''
    Write-Host " $n/3 " -ForegroundColor Black -BackgroundColor Cyan -NoNewline
    Write-Host "  $(T $zh $en)" -ForegroundColor Cyan
}
function Ask([string]$zh, [string]$en) { Read-Host "     $(T $zh $en)" }
function Rule { Write-Host ('  ' + ([string][char]0x2500) * 56) -ForegroundColor DarkGray }

function Fail([string]$zh, [string]$en, [int]$code) {
    Mark 'x' Red $zh $en
    Say '没有修改任何文件。' 'No files were changed.' 'DarkGray'
    Write-Host ''
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
# spice identifies a patch by sha256(gameCode + patch file id + name + description)
function Patch-Hash($p, [string]$id) { (Sha256 "$($p.gameCode)$id$($p.name)$($p.description)").ToLower() }
# on/off hashes of the knob fix: the current description first, then the earlier ones
function Get-KnobHashes([string]$id) {
    foreach ($d in @($KnobDesc) + $KnobDescOld) { Patch-Hash ([pscustomobject]@{ gameCode = 'KFC'; name = $KnobFixName; description = $d }) $id }
}
# a spice patch file is a top-level JSON array; Windows PowerShell 5.1 returns it as one object, so unroll it
function Read-Patches([string]$path) { @((ConvertFrom-Json ([IO.File]::ReadAllText($path))) | ForEach-Object { $_ }) }
# every file offset where the byte signature occurs ($text is the dll read as Latin-1)
function Find-All([string]$text, [string]$hex) {
    $sig = $Latin1.GetString((Bytes $hex))
    $i = $text.IndexOf($sig, [StringComparison]::Ordinal)
    while ($i -ge 0) { $i; $i = $text.IndexOf($sig, $i + 1, [StringComparison]::Ordinal) }
}

function New-Option([string]$name, [int]$offset, [string]$data) {
    [pscustomobject]@{ name = $name; patch = [pscustomobject]@{ offset = $offset; dllName = 'soundvoltex.dll'; data = $data } }
}

function Backup([string]$path) {
    $bak = "$path$BakSuffix"
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
    public class Info { public string Name; public bool Primary; public int Width, Height, Hz; public int[] Rates, GameRates; }
    public static List<Info> Get() {
        var list = new List<Info>();
        var dd = new DISPLAY_DEVICE(); dd.cb = Marshal.SizeOf(dd);
        for (int i = 0; EnumDisplayDevices(null, i, ref dd, 0); i++, dd.cb = Marshal.SizeOf(dd)) {
            if ((dd.StateFlags & 1) == 0) continue;  // not attached to the desktop
            var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(dm);
            if (!EnumDisplaySettings(dd.DeviceName, -1, ref dm)) continue;  // ENUM_CURRENT_SETTINGS
            var info = new Info { Name = dd.DeviceName, Primary = (dd.StateFlags & 4) != 0, Width = dm.dmPelsWidth, Height = dm.dmPelsHeight, Hz = dm.dmDisplayFrequency };
            var rates = new SortedSet<int>();
            var game = new SortedSet<int>();  // the game goes fullscreen at 1080x1920
            var m = new DEVMODE(); m.dmSize = (short)Marshal.SizeOf(m);
            for (int k = 0; EnumDisplaySettings(dd.DeviceName, k, ref m); k++) {
                if (m.dmDisplayFrequency <= 1) continue;
                if ((m.dmPelsWidth == info.Width && m.dmPelsHeight == info.Height) || (m.dmPelsWidth == info.Height && m.dmPelsHeight == info.Width)) rates.Add(m.dmDisplayFrequency);
                if ((m.dmPelsWidth == 1080 && m.dmPelsHeight == 1920) || (m.dmPelsWidth == 1920 && m.dmPelsHeight == 1080)) game.Add(m.dmDisplayFrequency);
            }
            if (info.Hz > 1) rates.Add(info.Hz);
            info.Rates = new int[rates.Count]; rates.CopyTo(info.Rates);
            info.GameRates = new int[game.Count]; game.CopyTo(info.GameRates);
            list.Add(info);
        }
        return list;
    }
}
'@ }

# model:dest:spec:rev:ext from prop\ea3-ident.xml, the key spice uses for auto apply
function Get-GameIdent {
    $ident = Join-Path $contents 'prop\ea3-ident.xml'
    if (-not (Test-Path -LiteralPath $ident)) { return $null }
    $soft = ([xml][IO.File]::ReadAllText($ident)).SelectSingleNode('/ea3_conf/soft')
    (@('model', 'dest', 'spec', 'rev', 'ext') | ForEach-Object { $soft.SelectSingleNode($_).InnerText }) -join ':'
}

# --- restore: undo what the installer changed, using the backups it made the first time.
# Patch files are replaced by their backup. In the spice settings only the installer's own entries are put
# back to their old values, so changes made in F4 after installing (key bindings, other patches) are kept.
function Test-Ours([string]$path) {
    @(Read-Patches $path | Where-Object { $_.name -eq $LimiterName -or $_.name -eq $KnobFixName }).Count -gt 0
}

# returns the ids of the patch files the installer had changed (their selections get reverted too)
function Restore-PatchFiles {
    $dir = Join-Path $contents 'patches'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    $paths = @(Get-ChildItem -LiteralPath $dir | Where-Object { $_.Name -like '*.json' -or $_.Name -like "*.json$BakSuffix" } |
        ForEach-Object { $_.FullName -replace ([regex]::Escape($BakSuffix) + '$'), '' } | Sort-Object -Unique)
    foreach ($path in $paths) {
        $bak = "$path$BakSuffix"
        $name = Split-Path -Leaf $path
        $exists = Test-Path -LiteralPath $path
        $ours = $exists -and (Test-Ours $path)
        if (Test-Path -LiteralPath $bak) {
            if ($ours -or -not $exists) {
                Move-Item -LiteralPath $bak -Destination $path -Force
                Ok "已还原  patches\$name" "Restored  patches\$name"
            } else {
                # replaced since the install (e.g. updated from spice's patch server), so it is clean already
                Remove-Item -LiteralPath $bak
                Ok "patches\$name 已经是原样，删除旧备份" "patches\$name is unmodified already; removed the old backup"
            }
        } elseif ($ours) {
            Warn "patches\$name 没有备份，文件保留原样（里面的补丁不会再被选中）" "patches\$name has no backup and is kept as is (its patches will no longer be selected)"
        } else { continue }
        [IO.Path]::GetFileNameWithoutExtension($path)
    }
}

function Restore-Selections([string[]]$ids) {
    $bak = "$managerFile$BakSuffix"
    if (-not $managerFile -or -not (Test-Path -LiteralPath $bak)) { return }
    $old = ConvertFrom-Json ([IO.File]::ReadAllText($bak))
    $cfg = ConvertFrom-Json ([IO.File]::ReadAllText($managerFile))
    if (-not $cfg.union_patches_enabled) { $cfg | Add-Member -NotePropertyName union_patches_enabled -NotePropertyValue ([pscustomobject]@{}) -Force }
    $lim = [pscustomobject]@{ gameCode = 'KFC'; name = $LimiterName; description = $LimiterDesc }
    foreach ($id in $ids) {
        $file = Join-Path $contents "patches\$id.json"
        $targets = @()
        if (Test-Path -LiteralPath $file) { $targets = @(Read-Patches $file | Where-Object { $_.name -in 'Game FPS Target', 'Note FPS Target' }) }
        foreach ($p in $targets + $lim) {
            $h = Patch-Hash $p $id
            $was = if ($old.union_patches_enabled) { $old.union_patches_enabled.$h } else { $null }
            if ($null -ne $was) { $cfg.union_patches_enabled | Add-Member -NotePropertyName $h -NotePropertyValue $was -Force }
            else { $cfg.union_patches_enabled.PSObject.Properties.Remove($h) }
        }
        $kHashes = @(Get-KnobHashes $id)
        if ($null -ne $cfg.patches_enabled) {
            $on = @($cfg.patches_enabled | Where-Object { $_ -and $kHashes -notcontains $_ })
            $on += @($kHashes | Where-Object { @($old.patches_enabled) -contains $_ })
            $cfg | Add-Member -NotePropertyName patches_enabled -NotePropertyValue $on -Force
        }
    }
    $ident = Get-GameIdent
    if ($ident -and @($old.auto_apply) -notcontains $ident -and @($cfg.auto_apply) -contains $ident) {
        $cfg | Add-Member -NotePropertyName auto_apply -NotePropertyValue @($cfg.auto_apply | Where-Object { $_ -and $_ -ne $ident }) -Force
    }
    Write-Text $managerFile (ConvertTo-Json -InputObject $cfg -Depth 20)
    Remove-Item -LiteralPath $bak
    Ok '已还原 spice2x 的补丁选择' 'Restored the patch selection in spice2x'
}

function Restore-Refresh {
    $bak = "$spiceXml$BakSuffix"
    if (-not $spiceXml -or -not (Test-Path -LiteralPath $bak)) { return }
    $oldBlock = [regex]::Match([IO.File]::ReadAllText($bak), $SdvxBlockRe)
    $text = [IO.File]::ReadAllText($spiceXml)
    $block = [regex]::Match($text, $SdvxBlockRe)
    if (-not $oldBlock.Success -or -not $block.Success) {
        Warn 'spicetools.xml 里没找到 Sound Voltex 的设置，Monitor Refresh Rate 没有还原（备份保留）' 'No Sound Voltex section in spicetools.xml; Monitor Refresh Rate was not restored (backup kept)'
        return
    }
    $was = [regex]::Match($oldBlock.Value, $RefreshRe)
    $now = [regex]::Match($block.Value, $RefreshRe)
    $new = $block.Value
    if ($was.Success -and $now.Success) { $new = $new.Remove($now.Index, $now.Length).Insert($now.Index, $was.Value) }
    elseif ($now.Success) { $new = ([regex]('\r?\n[ \t]*' + $RefreshRe)).Replace($new, '', 1) }  # the installer added the line
    if ($new -ne $block.Value) { Write-Text $spiceXml ($text.Remove($block.Index, $block.Length).Insert($block.Index, $new)) }
    Remove-Item -LiteralPath $bak
    $value = if ($was.Success -and $was.Groups[1].Value) { "$($was.Groups[1].Value) Hz" } else { T '未设置' 'not set' }
    Ok "已还原 Monitor Refresh Rate  $value" "Restored Monitor Refresh Rate  $value"
}

function Invoke-Restore {
    Write-Host ''
    Write-Host ' R ' -ForegroundColor Black -BackgroundColor Yellow -NoNewline
    Write-Host "  $(T '还原到安装前' 'Restore to before installing')" -ForegroundColor Yellow
    $dir = Join-Path $contents 'patches'
    $baks = @()
    if (Test-Path -LiteralPath $dir) { $baks += @(Get-ChildItem -LiteralPath $dir | Where-Object { $_.Name -like "*$BakSuffix" } | ForEach-Object { $_.FullName }) }
    foreach ($f in @($managerFile, $spiceXml)) { if ($f -and (Test-Path -LiteralPath "$f$BakSuffix")) { $baks += "$f$BakSuffix" } }
    if (-not $baks.Count) {
        Ok '没有找到安装器留下的备份，不需要还原' 'No backups from the installer were found; nothing to restore'
        return
    }
    Say '会用这些备份还原补丁文件，并把 spice2x 里的帧数补丁选择和 Monitor Refresh Rate 改回安装前；安装后你在 F4 里改的其他设置不受影响' 'These backups restore the patch files and put the frame rate patch selection and Monitor Refresh Rate in spice2x back to before installing; other settings you changed in F4 since are kept' 'DarkGray'
    foreach ($b in $baks) { Item (T '备份' 'Backup') $b }
    if (-not $Yes) {
        $ok = Ask '确定还原？(y/N)' 'Restore now? (y/N)'
        if ($ok -notmatch '^[yY]') { Fail '已取消' 'Cancelled' 9 }
    }
    $ids = @(Restore-PatchFiles)
    Restore-Selections $ids
    Restore-Refresh
    Write-Host ''
    Rule
    Write-Host ('  ' + (T '还原完成，重新启动游戏后生效' 'Restored. Restart the game for it to take effect')) -ForegroundColor Green
    Rule
}

Write-Host ''
Write-Host '  SDVX FPS Unlock  ' -ForegroundColor Black -BackgroundColor Cyan -NoNewline
Write-Host ('  ' + (T '解除 SOUND VOLTEX 的 120 帧限制' 'Lift the 120 FPS cap of SOUND VOLTEX')) -ForegroundColor DarkGray
Step 1 '检查游戏' 'Checking the game'

$contents = Find-Contents $GameDir
if (-not $contents) { $contents = Find-Contents (Split-Path -Parent $Here) }
if (-not $contents) { $contents = Find-Contents $Here }
while (-not $contents) {
    if ($Yes) { Fail '没找到游戏，请用 -GameDir 指定游戏文件夹。' 'Game not found; pass the game folder with -GameDir.' 1 }
    $in = Ask '没找到游戏，请把游戏文件夹拖进来或输入路径（直接回车退出）' 'Game not found. Drag the game folder here or type its path (Enter to quit)'
    if (-not $in) { exit 1 }
    $contents = Find-Contents $in.Trim('"')
    if (-not $contents) { Warn '这个文件夹里没有 contents\modules\soundvoltex.dll' 'contents\modules\soundvoltex.dll not found in this folder' }
}
Ok "游戏目录  $contents" "Game folder  $contents"

if (Get-Process -Name spice64 -ErrorAction SilentlyContinue) { Fail '游戏正在运行，请先关闭游戏。' 'The game is running. Close it first.' 3 }

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

# restore works on any game version, so it runs before the version checks below
if ($Restore) {
    Invoke-Restore
    Write-Host ''
    exit 0
}

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
Ok "游戏版本  $patchId" "Game version  $patchId"

$patches = Read-Patches $patchFile
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
$hits = @(Find-All $text $LimiterSig)
if ($hits.Count -ne 1) { Fail "找到 $($hits.Count) 处限帧器特征码（需要正好 1 处），这个版本不支持。" "Found $($hits.Count) frame limiter signatures (exactly 1 required); this version is not supported." 6 }
$lOff = $hits[0]

# menu knob filter: optional, the frame rate unlock works without it.
# Each span is checked on its own; which ones go into the patch is decided once the frame rate is known.
# true when the bytes at $at match the hex pattern ('??' matches any byte)
function Test-Bytes([int]$at, [string]$pattern) {
    $n = $pattern.Length / 2
    if ($at -lt 0 -or $at + $n -gt $dll.Length) { return $false }
    for ($i = 0; $i -lt $n; $i++) {
        $want = $pattern.Substring($i * 2, 2)
        if ($want -ne '??' -and $dll[$at + $i] -ne [Convert]::ToByte($want, 16)) { return $false }
    }
    $true
}
# finds one span of $KnobSpecs in the dll; .Error says why it does not fit this game version
function Get-KnobSpan($spec) {
    if ($spec.expected.Length -ne $spec.enabled.Length) { throw "Knob span '$($spec.name)': expected and enabled differ in length" }
    $span = [pscustomobject]@{ Spec = $spec; Offset = -1; Error = $null }
    $anchor = @(Find-All $text $spec.anchor)
    if ($anchor.Count -ne 1) { $span.Error = "signature found $($anchor.Count) times"; return $span }
    if (@($spec.guards | Where-Object { $_ -and -not (Test-Bytes ($anchor[0] + [int]$_.offset) $_.expected) }).Count) {
        $span.Error = 'branch targets differ'
        return $span
    }
    $span.Offset = $anchor[0] + [int]$spec.offset
    if (-not (Test-Bytes $span.Offset $spec.expected)) { $span.Error = 'instructions differ' }
    $span
}
$kHits = @(Find-All $text $KnobSig)
$knobSpans = @((ConvertFrom-Json $KnobSpecs) | ForEach-Object { $_ } | ForEach-Object { Get-KnobSpan $_ })

$xmlText = $null; $sdvxBlock = $null
if ($spiceXml) {
    $xmlText = [IO.File]::ReadAllText($spiceXml)
    $sdvxBlock = [regex]::Match($xmlText, $SdvxBlockRe)
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
Step 2 '选择帧数' 'Choosing the frame rate'
foreach ($d in $displays) {
    $tag = if ($d -eq $main -and $displays.Count -gt 1) { T '  ← 游戏用这块' '  ← used by the game' } else { '' }
    Item (T '显示器' 'Monitor') ('{0}  {1}x{2}  {3} {4} Hz{5}' -f $d.Name, $d.Width, $d.Height, (T '当前' 'now'), $d.Hz, $tag)
}
# "portrait" = the game runs 1080x1920 fullscreen on V-Sync. At start it looks for a 1080x1920 @ 120 Hz mode, which
# only exists while the monitor is rotated, and uses V-Sync if found; otherwise it asks for 60 Hz and runs on its own
# limiter. Launchers often rotate the monitor only while the game runs, so the mode the game asked for at its last
# launch (logged by spice) beats the desktop orientation right now, which is only the fallback.
$portrait = $main -and $main.Height -gt $main.Width
$lastMode = $null
if (Test-Path -LiteralPath $logFile) {
    $found = [regex]::Matches([IO.File]::ReadAllText($logFile, $Latin1), 'fullscreen display mode for adapter 0: Width: (\d+), Height: (\d+), RefreshRate: (\d+)')
    if ($found.Count) { $lastMode = $found[$found.Count - 1] }
}
if ($lastMode) {
    $portrait = [int]$lastMode.Groups[3].Value -eq 120
    Item (T '上次启动' 'Last launch') ('{0}x{1} @ {2} Hz  {3}' -f $lastMode.Groups[1].Value, $lastMode.Groups[2].Value, $lastMode.Groups[3].Value, $(if ($portrait) { T '（竖屏，垂直同步）' '(portrait, V-Sync)' } else { T '（横屏）' '(landscape)' }))
}
# portrait runs exclusive fullscreen at 1080x1920, so only that mode's refresh rates are usable there
$gameRates = if ($main) { @($main.GameRates) } else { @() }
$okRates = if ($portrait -and $gameRates.Count) { $gameRates } elseif ($main) { @($main.Rates) } else { @() }
if ($portrait) {
    Say '竖屏游戏会切到 1080x1920 全屏，下面是这个分辨率下支持的刷新率' 'Portrait: the game switches to 1080x1920 fullscreen; rates below are for that mode' 'DarkGray'
}
$maxHz = if ($okRates.Count) { ($okRates | Measure-Object -Maximum).Maximum } else { 0 }
if ($okRates.Count) {
    Item (T '支持  ' 'Rates  ') "$($okRates -join ' / ') Hz" Green
    Say '请填其中一个，尽量不要用和显示器不符的帧数' 'Pick one of these; avoid frame rates that do not match the monitor' 'DarkGray'
}

# --- target frame rate
$suggest = if ($maxHz) { [Math]::Min($MaxFps, [Math]::Max($MinFps, [int]$maxHz)) } else { 120 }
while ($Fps -lt $MinFps -or $Fps -gt $MaxFps) {
    if ($Yes -and $Fps -eq 0) { $Fps = $suggest; break }
    if ($Yes) { Fail "帧数需要在 $MinFps 到 $MaxFps 之间。" "The frame rate must be between $MinFps and $MaxFps." 7 }
    Write-Host ''
    $in = Ask "输入目标帧数（直接回车 = $suggest）" "Target FPS (Enter = $suggest)"
    if (-not $in) { $Fps = $suggest; break }
    $n = 0
    if (-not [int]::TryParse($in.Trim(), [ref]$n) -or $n -lt $MinFps -or $n -gt $MaxFps) {
        Warn "请输入 $MinFps 到 $MaxFps 之间的整数" "Enter a whole number between $MinFps and $MaxFps" 
        continue
    }
    $Fps = $n
}
Ok "目标帧数  $Fps FPS" "Target  $Fps FPS"

$supported = $main -and ($okRates -contains $Fps)
if ($main -and -not $supported) {
    Warn "$Fps 和显示器刷新率不符（支持 $($okRates -join ' / ') Hz），建议改用其中一个" "$Fps does not match the monitor ($($okRates -join ' / ') Hz); using one of them is recommended" 
    if ($portrait) {
        # portrait runs with V-Sync: frames follow the monitor, Live2D timing follows the limiter
        Say '竖屏是垂直同步定帧数，实际帧数会和设定不一致，Live2D 角色动画会变快或变慢' 'Portrait mode uses V-Sync, so the real frame rate will differ and Live2D animations will run too fast or slow' 'Yellow'
        if ($main.Rates -contains $Fps) {
            Say "$Fps Hz 只在桌面分辨率下有，1080x1920 全屏没有，所以不会设置 Monitor Refresh Rate（设了游戏会启动不了）" "$Fps Hz only exists at the desktop resolution, not in 1080x1920 fullscreen, so Monitor Refresh Rate is left alone (it would stop the game from starting)" 'Yellow'
        }
    } else {
        Say '帧数和刷新率对不上时画面会不顺滑或撕裂' 'A frame rate that does not match the refresh rate stutters or tears' 'Yellow'
        if ($Fps -gt $maxHz) { Say "显示器最高 $maxHz Hz，超出的帧也看不到" "The monitor tops out at $maxHz Hz; extra frames are not shown" 'Yellow' }
    }
    if (-not $Yes) {
        $ok = Ask '仍然继续？(y/N)' 'Continue anyway? (y/N)'
        if ($ok -notmatch '^[yY]') { Fail '已取消，请重新运行并填显示器支持的刷新率' 'Cancelled. Run again and enter a refresh rate your monitor supports' 8 }
    }
}

$Rates = @($Presets + $Fps | Sort-Object -Unique)

# --- Knob Fix. At multiples of 120 the filter samples on a 120 Hz clock and sees the same input as at 120 FPS.
# Between ticks it returns 0, so the sampler needs the three idle timeouts (counted in frames) switched to one second.
# Otherwise the filter only drops the frame-time gain (as in v1.3.0). Spans that do not fit this version are left out.
$knob = $null; $knobSampler = $false; $knobWhy = $null
$knobMissing = @($knobSpans | Where-Object { $_.Error } | ForEach-Object { $_.Spec.name })
if ($kHits.Count -eq 1) {
    $filter = $knobSpans[0]
    $timeouts = @($knobSpans | Where-Object { $null -ne $_.Spec.fpsOffset })
    $knobSampler = $Fps % 120 -eq 0 -and -not $filter.Error -and -not @($timeouts | Where-Object { $_.Error }).Count
    $mem = @(foreach ($s in $knobSpans) {
        $at = $s.Offset; $on = Bytes $s.Spec.enabled
        if ($s -eq $filter -and -not $knobSampler) {
            $at = $kHits[0] + [int]$s.Spec.fallback.offset; $on = Bytes $s.Spec.fallback.enabled
            if (-not (Test-Bytes $at $s.Spec.fallback.expected)) { throw 'Knob fix fallback is not inside $KnobSig' }
        } elseif ($s.Error) { continue }
        if ($null -ne $s.Spec.fpsOffset) { [Array]::Copy([BitConverter]::GetBytes([uint32]$Fps), 0, $on, [int]$s.Spec.fpsOffset, 4) }
        [pscustomobject]@{ offset = $at; dllName = 'soundvoltex.dll'; dataDisabled = Hex (Slice $dll $at $on.Length); dataEnabled = Hex $on }
    })
    $sorted = @($mem | Sort-Object offset)
    for ($i = 1; $i -lt $sorted.Count; $i++) {
        if ($sorted[$i - 1].offset + $sorted[$i - 1].dataEnabled.Length / 2 -gt $sorted[$i].offset) { $knobWhy = 'overlap' }
    }
    if (-not $knobWhy) {
        $knob = [pscustomobject]@{ name = $KnobFixName; description = $KnobDesc; gameCode = 'KFC'; type = 'memory'; patches = $mem }
    }
}

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
    description = $LimiterDesc
    gameCode = 'KFC'
    type = 'union'
    patches = @(foreach ($r in $Rates | Where-Object { $_ -ne 60 -or $Fps -eq 60 }) {
        New-Option ("$r FPS" + $(if ($r -eq 120) { ' (Default)' } else { '' })) $lOff ('BB' + (Le32 ($r * 1000)))
    })
}

$out = New-Object System.Collections.ArrayList
foreach ($p in $patches) {
    if ($p.name -eq $LimiterName -or $p.name -eq $KnobFixName) { continue }
    [void]$out.Add($p)
    if ($p.name -eq 'Note FPS Target') {
        [void]$out.Add($limiter)
        if ($knob) { [void]$out.Add($knob) }
    }
}
$knobOn = $knob -and $Fps -gt 120

Step 3 '写入设置' 'Applying settings'
Backup $patchFile
[IO.File]::WriteAllText($patchFile, (ConvertTo-Json -InputObject $out.ToArray() -Depth 20), $Utf8)
Ok '补丁文件已更新' 'Patch file updated'
if ($Fps -gt 120) {
    if (-not $knob) {
        $why = if ($knobWhy) { T '几处指令位置重叠' 'its instruction spans overlap' } else { T "旋钮滤波特征码找到 $($kHits.Count) 处，需要正好 1 处" "found $($kHits.Count) knob filter signatures, exactly 1 required" }
        Warn "这个版本没法加旋钮修复（$why）：高帧数下选曲界面旋钮转慢了可能没反应" "The knob fix was not added ($why): slow knob turns may not register in menus at high frame rates"
    } elseif ($knobMissing.Count) {
        Warn "旋钮修复只装了一部分，这个版本有 $($knobMissing.Count) 处指令对不上，旋钮可能比 120 FPS 时迟钝" "Only part of the knob fix was added; $($knobMissing.Count) instruction spans do not fit this game version, so knobs may feel less responsive than at 120 FPS"
        foreach ($m in $knobMissing) { Say "- $m" "- $m" 'DarkGray' }
    } elseif (-not $knobSampler) {
        Say "$Fps 不是 120 的倍数，旋钮修复只修了一部分（快转门槛仍按帧算），中速转动可能偏迟钝；240 / 360 / 480 这类帧数旋钮手感和 120 FPS 时基本一样" "$Fps is not a multiple of 120, so the knob fix is partial (the fast-turn threshold still counts frames) and medium-speed turns may feel sluggish; at 240 / 360 / 480 and other multiples knobs feel essentially the same as at 120 FPS" 'DarkGray'
    }
}

# --- select the patches in spice2x's patch manager
$selected = $false
if ($managerFile) {
    $cfg = ConvertFrom-Json ([IO.File]::ReadAllText($managerFile))
    if (-not $cfg.union_patches_enabled) { $cfg | Add-Member -NotePropertyName union_patches_enabled -NotePropertyValue ([pscustomobject]@{}) -Force }
    foreach ($p in @($game, $note, $limiter)) {
        $opt = $p.patches | Where-Object { $_.name -match "^$Fps FPS( \(Default\))?$" } | Select-Object -First 1
        $cfg.union_patches_enabled | Add-Member -NotePropertyName (Patch-Hash $p $patchId) -NotePropertyValue $opt.name -Force
    }
    # on/off patches are a plain list of enabled hashes; the knob fix is only wanted above 120 FPS
    # hashes of earlier descriptions are dropped too, they no longer match any patch
    if ($knobOn -or $null -ne $cfg.patches_enabled) {
        $kHashes = @(Get-KnobHashes $patchId)
        $enabled = @($cfg.patches_enabled | Where-Object { $_ -and $kHashes -notcontains $_ })
        if ($knobOn) { $enabled += $kHashes[0] }
        $cfg | Add-Member -NotePropertyName patches_enabled -NotePropertyValue $enabled -Force
    }
    # auto apply makes spice apply the saved selection at every launch
    $gameIdent = Get-GameIdent
    if ($gameIdent) {
        $auto = @($cfg.auto_apply | Where-Object { $_ })
        if ($auto -notcontains $gameIdent) { $cfg | Add-Member -NotePropertyName auto_apply -NotePropertyValue @($auto + $gameIdent) -Force }
    }
    Backup $managerFile
    Write-Text $managerFile (ConvertTo-Json -InputObject $cfg -Depth 20)
    $selected = $true
    Ok "spice2x 已选中三项补丁  $Fps FPS" "Selected all three patches in spice2x  $Fps FPS"
    if ($knobOn) { Ok "旋钮修复已开启  $KnobFixName" "Knob fix turned on  $KnobFixName" }
} else {
    Warn '没找到 spice2x 的补丁设置（游戏还没启动过？），需要手动选择' 'spice2x patch settings not found (game never launched?); select the patches manually'
}

# --- Monitor Refresh Rate (-graphics-force-refresh): needed in portrait, kept in sync if already set.
# It forces the game's 1080x1920 fullscreen mode to this rate, so it is only written when that mode exists;
# otherwise the game fails to start.
$refreshDone = $false; $refreshChanged = $false
if ($sdvxBlock -and ($gameRates -contains $Fps)) {
    $block = $sdvxBlock.Value
    $m = [regex]::Match($block, $RefreshRe)
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
            $refreshChanged = $true
        }
        $refreshDone = $true
        Ok "Monitor Refresh Rate  $Fps Hz" "Monitor Refresh Rate  $Fps Hz" 
    }
} elseif ($sdvxBlock -and $gameRates.Count) {
    # a value the 1080x1920 mode lacks (e.g. written by an older installer) keeps the game from starting; clear it
    $m = [regex]::Match($sdvxBlock.Value, '<option name="graphics-force-refresh" value="(\d+)"\s*/>')
    if ($m.Success -and ($gameRates -notcontains [int]$m.Groups[1].Value)) {
        $newBlock = $sdvxBlock.Value.Remove($m.Index, $m.Length).Insert($m.Index, '<option name="graphics-force-refresh" value=""/>')
        Backup $spiceXml
        Write-Text $spiceXml ($xmlText.Remove($sdvxBlock.Index, $sdvxBlock.Length).Insert($sdvxBlock.Index, $newBlock))
        Warn "原来的 Monitor Refresh Rate（$($m.Groups[1].Value) Hz）在 1080x1920 下不可用，已清除" "The previous Monitor Refresh Rate ($($m.Groups[1].Value) Hz) does not exist at 1080x1920 and was cleared" 
    }
}

Write-Host ''
Rule
if ($selected) {
    Write-Host ('  ' + (T '安装完成！直接启动游戏，帧数显示在 ESC 菜单里打开' 'Done! Start the game; turn on the FPS counter in the ESC menu')) -ForegroundColor Green
} else {
    Write-Host ('  ' + (T "安装完成。启动游戏 -> F4 -> Patches，把下面三项都选成 $Fps FPS：" "Done. Start the game -> F4 -> Patches and set these three to $Fps FPS:")) -ForegroundColor Green
    Write-Host '     Game FPS Target'
    Write-Host '     Note FPS Target'
    Write-Host "     $LimiterName"
    if ($knobOn) { Write-Host ('  ' + (T "再勾上 $KnobFixName（选曲界面旋钮修复）" "Also turn on $KnobFixName (menu knob fix)")) -ForegroundColor Green }
    Write-Host ('  ' + (T '然后点 Save，重启游戏' 'Then click Save and restart the game')) -ForegroundColor Green
}
if ($portrait -and -not $refreshDone -and ($gameRates -contains $Fps)) {
    Say "竖屏显示器还要设：F4 -> Options -> Display -> Monitor -> Monitor Refresh Rate 填 $Fps，再重启游戏" "Portrait monitor: also set F4 -> Options -> Display -> Monitor -> Monitor Refresh Rate to $Fps and restart" 'Yellow'
}
if ($refreshChanged) {
    Say '游戏启动不了的话：重新运行 install.bat 填 120，并把 contents\log.txt 发给作者' 'If the game no longer starts: run install.bat again, enter 120 and send contents\log.txt to the author' 'Yellow'
}
Say '想换帧数，重新运行 install.bat 即可' 'Run install.bat again to change the frame rate' 'DarkGray'
Rule
Write-Host ''
