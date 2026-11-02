param([string]$GameDir)

$ErrorActionPreference = 'Stop'
$Rates = 60, 120, 144, 165, 180, 185, 240, 300
$LimiterName = 'Frame Limiter Target (Experimental)'
# mov ebx, 120000 ; mov edx, ebx ; mov rcx, rax ; call -- sets the game's internal frame limiter (mHz)
$LimiterSig = 'BBC0D401008BD3488BC8E8'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Latin1 = [Text.Encoding]::GetEncoding(28591)

function Fail([string]$msg, [int]$code) {
    Write-Host $msg -ForegroundColor Red
    Write-Host '没有修改任何文件。'
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

function New-Option([string]$name, [int]$offset, [string]$data) {
    [pscustomobject]@{ name = $name; patch = [pscustomobject]@{ offset = $offset; dllName = 'soundvoltex.dll'; data = $data } }
}

Write-Host '=== SDVX 帧数解锁补丁（通用版）===' -ForegroundColor Cyan

$contents = Find-Contents $GameDir
if (-not $contents) { $contents = Find-Contents (Split-Path -Parent $Here) }
if (-not $contents) { $contents = Find-Contents $Here }
while (-not $contents) {
    $in = Read-Host '没找到游戏。请输入 LAZY_KFC 文件夹路径（直接回车退出）'
    if (-not $in) { exit 1 }
    $contents = Find-Contents $in.Trim('"')
    if (-not $contents) { Write-Host '这个文件夹里没有 contents\modules\soundvoltex.dll' -ForegroundColor Yellow }
}
Write-Host "游戏目录: $contents"

if (Get-Process -Name spice64 -ErrorAction SilentlyContinue) { Fail '游戏正在运行，请先关闭游戏再安装。' 3 }

# --- identify the game version from the PE header, the same way spice names its patch files
$dll = [IO.File]::ReadAllBytes((Join-Path $contents 'modules\soundvoltex.dll'))
$pe = [BitConverter]::ToInt32($dll, 0x3C)
$stamp = [BitConverter]::ToUInt32($dll, $pe + 8)
$entry = [BitConverter]::ToUInt32($dll, $pe + 24 + 16)
$patchFile = Join-Path $contents ('patches\KFC-{0:x8}_{1:x}.json' -f $stamp, $entry)
if (-not (Test-Path -LiteralPath $patchFile)) {
    Fail ("找不到这个版本的补丁文件: $patchFile`n你的整合包里没有这个游戏版本的补丁数据，无法安装。") 2
}
Write-Host "补丁文件: $patchFile"

$json = [IO.File]::ReadAllText($patchFile)
# Windows PowerShell 5.1 emits a top-level JSON array as a single object; pipe it to unroll
$patches = @((ConvertFrom-Json $json) | ForEach-Object { $_ })
$game = $patches | Where-Object { $_.name -eq 'Game FPS Target' } | Select-Object -First 1
$note = $patches | Where-Object { $_.name -eq 'Note FPS Target' } | Select-Object -First 1
if (-not $game -or -not $note) { Fail '补丁文件里没有 Game FPS Target / Note FPS Target，无法安装。' 4 }

# --- Game FPS Target: a double constant (60.0); rewrite the top two bytes so every option covers the same range
$g60 = $game.patches | Where-Object { $_.name -like '60 FPS*' } | Select-Object -First 1
if (-not $g60) { Fail 'Game FPS Target 里没有 60 FPS 选项。' 4 }
$gOff = [int]$g60.patch.offset
if ($g60.patch.data.Length -eq 4) { $gOff += 1 }  # already widened by an earlier install
if ((Hex (Slice $dll ($gOff - 6) 8)) -ne '0000000000004E40') { Fail 'Game FPS Target 的位置和游戏文件对不上。' 5 }
$game.patches = @(foreach ($r in $Rates) {
    $b = [BitConverter]::GetBytes([double]$r)
    New-Option ("$r FPS" + $(if ($r -eq 60) { ' (Default)' } else { '' })) ($gOff - 1) (Hex (Slice $b 5 2))
})

# --- Note FPS Target: replace the refresh-rate read with mov eax, <rate>
$n60 = $note.patches | Where-Object { $_.name -like '60 FPS*' } | Select-Object -First 1
$n120 = $note.patches | Where-Object { $_.name -like '120 FPS*' } | Select-Object -First 1
if (-not $n60 -or -not $n120 -or $n120.patch.data -notmatch '^B878000000') { Fail 'Note FPS Target 的格式和预期不一样。' 4 }
$nOff = [int]$n60.patch.offset
if ((Hex (Slice $dll $nOff ($n60.patch.data.Length / 2))) -ne $n60.patch.data.ToUpper()) { Fail 'Note FPS Target 的位置和游戏文件对不上。' 5 }
$tail = $n120.patch.data.Substring(10)
$note.patches = @($n60) + @(foreach ($r in $Rates | Where-Object { $_ -ne 60 }) { New-Option "$r FPS" $nOff ('B8' + (Le32 $r) + $tail) })

# --- internal frame limiter: find the instruction by signature, it must be unique
$text = $Latin1.GetString($dll)
$sig = $Latin1.GetString((Bytes $LimiterSig))
$hits = @(); $i = $text.IndexOf($sig, [StringComparison]::Ordinal)
while ($i -ge 0) { $hits += $i; $i = $text.IndexOf($sig, $i + 1, [StringComparison]::Ordinal) }
if ($hits.Count -ne 1) { Fail "在游戏文件里找到 $($hits.Count) 处限帧器特征码（需要正好 1 处），这个版本不支持。" 6 }
$lOff = $hits[0]
$limiter = [pscustomobject]@{
    name = $LimiterName
    description = "Changes the game's internal frame limiter (120 FPS by default). Use the same value for Game FPS Target and Note FPS Target. Parts of the game may run faster than normal."
    gameCode = 'KFC'
    type = 'union'
    patches = @(foreach ($r in $Rates | Where-Object { $_ -ne 60 }) {
        New-Option ("$r FPS" + $(if ($r -eq 120) { ' (Default)' } else { '' })) $lOff ('BB' + (Le32 ($r * 1000)))
    })
}

$out = New-Object System.Collections.ArrayList
foreach ($p in $patches) {
    if ($p.name -eq $LimiterName) { continue }
    [void]$out.Add($p)
    if ($p.name -eq 'Note FPS Target') { [void]$out.Add($limiter) }
}

$backup = "$patchFile.before-fps-unlock.bak"
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $patchFile -Destination $backup
    Write-Host "已备份原补丁文件: $backup"
} else {
    Write-Host "已存在备份，保留不覆盖: $backup"
}
$newJson = ConvertTo-Json -InputObject $out.ToArray() -Depth 20
[IO.File]::WriteAllText($patchFile, $newJson, (New-Object Text.UTF8Encoding $false))

Write-Host '安装完成。' -ForegroundColor Green
Write-Host ''
Write-Host '接下来：启动游戏 -> F4 -> Patches，把下面三项选成同一个数（如 300 FPS），点 Save，再重启游戏：'
Write-Host '  Game FPS Target'
Write-Host '  Note FPS Target'
Write-Host "  $LimiterName"
Write-Host ''
Write-Host '竖屏显示器（1080x1920）还要设：F4 -> Options -> Display -> Monitor -> Monitor Refresh Rate 填同一个数，再重启游戏。'
