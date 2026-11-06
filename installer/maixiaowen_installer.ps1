# One-click installer for the Maixiaowen Ink mod for Phantom Blade Zero (Steam version).
# Installing copies only this mod's own files, keeps any UE4SS that is already there and leaves mods.txt
# alone: the mod folder carries enabled.txt, which UE4SS loads by itself. Uninstalling moves this mod's
# files to the Recycle Bin and removes only this mod's own line from mods.txt.
param(
    [ValidateSet('install', 'uninstall', 'detect')]
    [string]$Action = 'install',
    [ValidateSet('mod', 'voice')]
    [string]$Part = 'mod',
    [string]$GameDir = '',
    [switch]$Yes,
    [switch]$NoRecycle
)

$ErrorActionPreference = 'Stop'
# Lets the .bat launchers be tested against a mock game folder.
if (-not $GameDir -and $env:MAIXIAOWEN_GAME_DIR) { $GameDir = $env:MAIXIAOWEN_GAME_DIR }
$package = Split-Path -Parent $PSScriptRoot
$steamAppId = '4115450'
$exeRelative = 'platform\steam\PBZ.exe'
$paksRelative = 'ProjectPBZ\Content\Paks\~mods'
$ue4ssDllRelative = 'platform\steam\ue4ss\UE4SS.dll'
$proxyRelative = 'platform\steam\dwmapi.dll'
$modFolderRelative = 'platform\steam\ue4ss\Mods\MaixiaowenInk'
$helpersRelative = 'platform\steam\ue4ss\Mods\shared\UEHelpers\UEHelpers.lua'
$modsListRelative = 'platform\steam\ue4ss\Mods\mods.txt'
$appearancePaks = 'MaixiaowenInk_P.pak', 'MaixiaowenInk_P.utoc', 'MaixiaowenInk_P.ucas'
$voicePaks = 'MaixiaowenVoiceCN_P.pak', 'MaixiaowenVoiceCN_P.utoc', 'MaixiaowenVoiceCN_P.ucas'

function Say([string]$text, [string]$color = 'Gray') { Write-Host $text -ForegroundColor $color }

function Fail([string]$text) {
    Say ''
    Say $text 'Red'
    exit 1
}

function Ask([string]$question) {
    if ($Yes) { return $true }
    while ($true) {
        $answer = (Read-Host "$question（直接回车 = 是，输入 N = 否）").Trim()
        if ($answer -eq '' -or $answer -match '^[Yy是]') { return $true }
        if ($answer -match '^[Nn否]') { return $false }
    }
}

# Accepts the game folder or anything inside it, such as PBZ.exe or platform\steam.
function Get-GameRoot([string]$path) {
    if (-not $path) { return $null }
    $path = $path.Trim().Trim('"').Trim("'")
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
    $item = Get-Item -LiteralPath $path
    $dir = if ($item.PSIsContainer) { $item.FullName } else { $item.DirectoryName }
    while ($dir) {
        if ((Test-Path -LiteralPath (Join-Path $dir $exeRelative)) -and (Test-Path -LiteralPath (Join-Path $dir 'ProjectPBZ'))) {
            return [IO.Path]::GetFullPath($dir).TrimEnd('\')
        }
        $dir = Split-Path -Parent $dir
    }
    return $null
}

function Get-SteamLibraries {
    $seen = @{}
    $libraries = New-Object System.Collections.ArrayList
    $roots = @()
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($props) {
            if ($props.SteamPath) { $roots += $props.SteamPath }
            if ($props.InstallPath) { $roots += $props.InstallPath }
        }
    }
    foreach ($root in $roots) {
        $candidates = @($root -replace '/', '\')
        $vdf = Join-Path $candidates[0] 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                $candidates += ($match.Groups[1].Value -replace '\\\\', '\')
            }
        }
        foreach ($library in $candidates) {
            $keyName = $library.TrimEnd('\').ToLowerInvariant()
            if (-not $seen.ContainsKey($keyName)) {
                $seen[$keyName] = $true
                [void]$libraries.Add($library.TrimEnd('\'))
            }
        }
    }
    return $libraries
}

function Find-GameRoots {
    $found = [ordered]@{}
    $paths = New-Object System.Collections.ArrayList
    # The zip may have been extracted inside the game folder.
    [void]$paths.Add($package)
    foreach ($key in "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App $steamAppId",
                     "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App $steamAppId") {
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($props -and $props.InstallLocation) { [void]$paths.Add($props.InstallLocation) }
    }
    foreach ($library in (Get-SteamLibraries)) {
        $manifest = Join-Path $library "steamapps\appmanifest_$steamAppId.acf"
        if (Test-Path -LiteralPath $manifest) {
            $match = [regex]::Match([IO.File]::ReadAllText($manifest), '"installdir"\s+"([^"]+)"')
            if ($match.Success) { [void]$paths.Add((Join-Path $library ('steamapps\common\' + $match.Groups[1].Value))) }
        }
        [void]$paths.Add((Join-Path $library 'steamapps\common\PBZ'))
    }
    foreach ($path in $paths) {
        $root = Get-GameRoot $path
        if ($root -and -not $found.Contains($root.ToLowerInvariant())) { $found[$root.ToLowerInvariant()] = $root }
    }
    return @($found.Values)
}

function Read-GameRoot {
    Say '请在 Steam 里右键《影之刃零》→「管理」→「浏览本地文件」，把打开的那个文件夹拖进这个窗口（或粘贴它的路径），再按回车。'
    while ($true) {
        $typed = Read-Host '游戏目录'
        if (-not $typed.Trim()) { Fail '已取消，没有做任何改动。' }
        $root = Get-GameRoot $typed
        if ($root) { return $root }
        Say '这个位置里没有找到 platform\steam\PBZ.exe，请再试一次（直接回车取消）。' 'Yellow'
    }
}

function Select-GameRoot([string]$question) {
    if ($GameDir) {
        $root = Get-GameRoot $GameDir
        if (-not $root) { Fail "这个位置不是《影之刃零》Steam 版的游戏目录：$GameDir" }
        return $root
    }
    $roots = @(Find-GameRoots)
    if ($roots.Count -eq 0) {
        if ($Yes) { Fail '没有找到游戏目录。' }
        Say '没有自动找到游戏目录。' 'Yellow'
        return Read-GameRoot
    }
    $choice = 0
    if ($roots.Count -gt 1 -and -not $Yes) {
        Say '找到多个游戏目录：' 'Cyan'
        for ($i = 0; $i -lt $roots.Count; $i++) { Say ('  {0}. {1}' -f ($i + 1), $roots[$i]) }
        while ($true) {
            $typed = (Read-Host '输入编号（直接回车 = 1）').Trim()
            if (-not $typed) { break }
            $number = 0
            if ([int]::TryParse($typed, [ref]$number) -and $number -ge 1 -and $number -le $roots.Count) { $choice = $number - 1; break }
        }
    }
    Say ''
    Say "游戏目录：$($roots[$choice])" 'Cyan'
    if (Ask $question) { return $roots[$choice] }
    return Read-GameRoot
}

function Wait-GameClosed([string]$root) {
    while ($true) {
        $running = @(Get-Process -Name 'PBZ' -ErrorAction SilentlyContinue | Where-Object {
            $path = $null
            try { $path = $_.Path } catch { }
            (-not $path) -or $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)
        })
        if ($running.Count -eq 0) { return }
        if ($Yes) { Fail '游戏正在运行，请先完全退出游戏。' }
        Say '游戏正在运行。请先完全退出游戏，然后回到这里按回车。' 'Yellow'
        [void](Read-Host)
    }
}

# Files listed in the package's SHA256.json under a prefix, checked to exist before anything is copied.
function Get-Payload([string]$prefix) {
    $manifestPath = Join-Path $package 'SHA256.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { Fail '找不到 SHA256.json。请先把整个压缩包解压出来，再运行解压后文件夹里的安装程序。' }
    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    $items = New-Object System.Collections.ArrayList
    foreach ($property in $manifest.PSObject.Properties) {
        if ($property.Name.StartsWith($prefix)) {
            $source = Join-Path $package ($property.Name -replace '/', '\')
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { Fail "压缩包没有解压完整，缺少 $($property.Name)。请把整个压缩包解压出来后再运行。" }
            [void]$items.Add([pscustomobject]@{
                Relative = ($property.Name.Substring($prefix.Length) -replace '/', '\')
                Source = $source
                Hash = [string]$property.Value
                Bytes = (Get-Item -LiteralPath $source).Length
            })
        }
    }
    return $items
}

function Copy-Payload($items, [string]$root) {
    $needed = 0
    foreach ($item in $items) {
        $target = Join-Path $root $item.Relative
        $existing = if (Test-Path -LiteralPath $target -PathType Leaf) { (Get-Item -LiteralPath $target).Length } else { 0 }
        $needed += [Math]::Max(0, $item.Bytes - $existing)
    }
    $drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($root))
    if ($drive.AvailableFreeSpace -lt $needed + 100MB) {
        Fail ('{0} 盘空间不够：需要约 {1:N0} MB，现在只剩 {2:N0} MB。' -f $drive.Name.TrimEnd('\'), ($needed / 1MB + 100), ($drive.AvailableFreeSpace / 1MB))
    }
    $index = 0
    foreach ($item in $items) {
        $index++
        $target = Join-Path $root $item.Relative
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        Say ('  [{0}/{1}] {2}' -f $index, $items.Count, $item.Relative)
        Copy-Item -LiteralPath $item.Source -Destination $target -Force
    }
    Say '  正在校验复制的文件…'
    foreach ($item in $items) {
        $target = Join-Path $root $item.Relative
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $item.Hash) {
            Fail "复制后校验失败：$($item.Relative)。请确认磁盘空间足够后重新运行。"
        }
    }
}

function Install-Mod([string]$root) {
    $items = @(Get-Payload 'MOD/')
    $loader = @(Get-Payload 'UE4SS_PBZ_Optional/')
    $extra = @()
    Say ''
    if (Test-Path -LiteralPath (Join-Path $root $ue4ssDllRelative)) {
        Say '检测到已经装有 UE4SS：保留你现有的加载器、设置和其他 MOD，不做改动。'
        if (-not (Test-Path -LiteralPath (Join-Path $root $helpersRelative))) {
            $extra = @($loader | Where-Object { $_.Relative -eq $helpersRelative })
            Say '你的 UE4SS 里缺少本 MOD 需要的 UEHelpers，会补上这一个文件。'
        }
    } elseif (Test-Path -LiteralPath (Join-Path $root $proxyRelative)) {
        Fail 'platform\steam 里已经有一个 dwmapi.dll，但没有 UE4SS。为了不破坏你在用的其他工具，安装已停止，没有做任何改动。'
    } else {
        Say '没有检测到 UE4SS：会一起装上本包自带的 UE4SS 加载器。'
        $extra = $loader
    }
    Say '会复制本 MOD 的外观文件和脚本，不修改 mods.txt，不碰其他 MOD。'
    if (-not (Ask '开始安装吗')) { Fail '已取消，没有做任何改动。' }
    Say ''
    Copy-Payload (@($items) + @($extra)) $root
    $obsolete = Join-Path $root "$modFolderRelative\Scripts\variant.txt"
    if (Test-Path -LiteralPath $obsolete) { Remove-Item -LiteralPath $obsolete -Force }
    Say ''
    Say '安装完成，文件已校验。启动游戏即可。' 'Green'
    Say '按键：F6 切换 90% / 正常大小，F7 眨眼，F8 眼球转动，F9 物理，F10 切回原版主角。'
    Say '想要女声战斗语音：解压语音包，双击里面的「一键安装语音.bat」。'
}

function Install-Voice([string]$root) {
    $items = @(Get-Payload 'MOD/')
    Say ''
    Say '会复制中文战斗语音的 3 个文件（约 250 MB），不碰其他 MOD。语音只在游戏语音设为中文时生效。'
    if (-not (Test-Path -LiteralPath (Join-Path $root "$paksRelative\$($appearancePaks[0])"))) {
        Say '提示：没有检测到外观 MOD。语音包可以单独使用，建议配合外观 MOD 一起装。' 'Yellow'
    }
    if (-not (Ask '开始安装吗')) { Fail '已取消，没有做任何改动。' }
    Say ''
    Copy-Payload $items $root
    Say ''
    Say '语音安装完成，文件已校验。启动游戏即可。' 'Green'
}

function Remove-Path([string]$path) {
    if ($NoRecycle) {
        Remove-Item -LiteralPath $path -Recurse -Force
        return
    }
    Add-Type -AssemblyName Microsoft.VisualBasic
    if (Test-Path -LiteralPath $path -PathType Container) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
}

# Removes only lines that enable or disable this mod, keeping the file's encoding and line endings.
function Remove-ModsListEntry([string]$root, [bool]$apply) {
    $path = Join-Path $root $modsListRelative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $bytes = [IO.File]::ReadAllBytes($path)
    $reader = New-Object IO.StreamReader($path, $true)
    $text = $reader.ReadToEnd()
    $encoding = $reader.CurrentEncoding
    $reader.Close()
    $hasBom = ($bytes.Length -ge 2) -and (($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) -or ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))
    if (-not $hasBom) { $encoding = New-Object Text.UTF8Encoding($false) }
    $lines = @([regex]::Split($text, '(?<=\n)'))
    $kept = @($lines | Where-Object { $_ -notmatch '^[ \t]*MaixiaowenInk[ \t]*:' })
    if ($kept.Count -eq $lines.Count) { return $false }
    if ($apply) {
        Copy-Item -LiteralPath $path -Destination "$path.maixiaowen-backup" -Force
        $writer = New-Object IO.StreamWriter($path, $false, $encoding)
        $writer.Write(($kept -join ''))
        $writer.Close()
    }
    return $true
}

function Uninstall([string]$root, [bool]$appearance) {
    $paths = @()
    if ($appearance) {
        $paths += $appearancePaks | ForEach-Object { Join-Path $root "$paksRelative\$_" }
        $paths += Join-Path $root $modFolderRelative
    }
    $paths += $voicePaks | ForEach-Object { Join-Path $root "$paksRelative\$_" }
    $existing = @($paths | Where-Object { Test-Path -LiteralPath $_ })
    $listed = $appearance -and (Remove-ModsListEntry $root $false)
    Say ''
    if ($existing.Count -eq 0 -and -not $listed) {
        Say '没有找到需要删除的文件，本 MOD 可能已经卸载过了。' 'Green'
        return
    }
    Say '会把下面这些本 MOD 的文件移到回收站：'
    foreach ($path in $existing) { Say ('  ' + $path.Substring($root.Length + 1)) }
    if ($listed) { Say "  并去掉 $modsListRelative 里本 MOD 的那一行（原文件另存为 mods.txt.maixiaowen-backup）" }
    Say 'UE4SS 加载器和其他 MOD 都不动。'
    if (-not (Ask '确定卸载吗')) { Fail '已取消，没有做任何改动。' }
    foreach ($path in $existing) { Remove-Path $path }
    if ($listed) { [void](Remove-ModsListEntry $root $true) }
    Say ''
    Say '卸载完成。' 'Green'
    if ($appearance) {
        Say 'UE4SS 加载器保留着，其他 MOD 可能还在用它。如果确定没有别的 MOD 需要，可以自己删除 platform\steam\dwmapi.dll 和 platform\steam\ue4ss 文件夹。'
    }
}

try {
    $title = if ($Part -eq 'voice') { '麦晓雯中文战斗语音' } else { '麦晓雯「水墨云图」MOD' }
    $verb = if ($Action -eq 'uninstall') { '卸载' } else { '安装' }
    if ($Action -eq 'detect') {
        foreach ($root in (Find-GameRoots)) { Say $root }
        exit 0
    }
    Say "$title · $verb" 'Cyan'
    Say '----------------------------------------'
    $root = Select-GameRoot $(if ($Action -eq 'uninstall') { '从这个目录卸载吗' } else { '安装到这个目录吗' })
    Wait-GameClosed $root
    if ($Action -eq 'install') {
        if ($Part -eq 'voice') { Install-Voice $root } else { Install-Mod $root }
    } else {
        Uninstall $root ($Part -eq 'mod')
    }
    exit 0
} catch {
    Say ''
    Say ('出错了：' + $_.Exception.Message) 'Red'
    Say '如果提示“拒绝访问”，请右键这个 .bat 文件，选「以管理员身份运行」后再试。'
    exit 1
}
