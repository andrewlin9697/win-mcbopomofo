<#
.SYNOPSIS
把小麥注音的使用者檔備份到 Google 雲端硬碟(單向複製、只新增),也可以從備份還原。

.DESCRIPTION
本 fork 自己加的腳本(不是官方檔案),說明見 MY-SETUP.md。Windows 內建的 PowerShell 5.1 就能執行,不需要系統管理員。

備份(不加參數):把 %APPDATA%\WinMcBopomofo 裡的檔案(user.txt、exclude.txt、mcbopomofo.ini 等,不含子資料夾)
複製到 Google 雲端硬碟電腦版的「我的雲端硬碟\小麥注音備份\日期-時間\」。
內容和最近一份備份完全一樣就不再備份。不會刪除或修改任何舊備份,也不會從雲端硬碟複製任何東西回來。

-Register    先備份一次,再建立每天自動備份的工作排程(會把這個腳本複製到 %LOCALAPPDATA%\WinMcBopomofoBackup\)
-Unregister  刪除工作排程
-Restore     從指定的備份資料夾還原。會先把目前的檔案備份到 %APPDATA%\WinMcBopomofo\backup\,
             暫停小麥注音 Server、複製檔案、再啟動 Server。備份裡沒有的檔案不會被刪除。

.PARAMETER Destination
備份要放的資料夾。沒指定時自動找 Google 雲端硬碟裡的「我的雲端硬碟」(或「My Drive」),放在裡面的「小麥注音備份」。

.PARAMETER Force
-Restore 時不詢問,直接還原。

.PARAMETER UserDir
小麥注音的使用者資料夾,預設 %APPDATA%\WinMcBopomofo。
#>
[CmdletBinding(DefaultParameterSetName = 'Backup')]
param(
    [Parameter(ParameterSetName = 'Backup')]
    [Parameter(ParameterSetName = 'Register')]
    [string]$Destination,

    [Parameter(ParameterSetName = 'Register', Mandatory = $true)]
    [switch]$Register,

    [Parameter(ParameterSetName = 'Unregister', Mandatory = $true)]
    [switch]$Unregister,

    [Parameter(ParameterSetName = 'Restore', Mandatory = $true)]
    [string]$Restore,

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$Force,

    [string]$UserDir = (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'WinMcBopomofo')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName = '小麥注音雲端備份'
$BackupFolderName = '小麥注音備份'
$DriveFolderNames = @('我的雲端硬碟', 'My Drive')
$InstallDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WinMcBopomofoBackup'
$LogPath = Join-Path $InstallDir 'backup.log'
$SnapshotPattern = '^\d{8}-\d{6}(-\d+)?$'
# 函式裡的 $PSBoundParameters 是函式自己的,這裡先記下來
$UserDirGiven = $PSBoundParameters.ContainsKey('UserDir')

function Write-Log([string]$Message) {
    try {
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
        [IO.File]::AppendAllText($LogPath, "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message`r`n", (New-Object System.Text.UTF8Encoding($true)))
    } catch {
        Write-Warning "寫不進紀錄檔 ${LogPath}:$($_.Exception.Message)"
    }
}

# 讀檔時允許小麥注音同時在寫,不會擋到它
function Read-Bytes([string]$Path) {
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
    try {
        $ms = New-Object IO.MemoryStream
        $fs.CopyTo($ms)
        return , $ms.ToArray()
    } finally {
        $fs.Dispose()
    }
}

function Get-Sha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($Bytes))
    } finally {
        $sha.Dispose()
    }
}

function Find-BackupDestination {
    if ($Destination) { return $Destination }
    # 串流模式是一個磁碟機(預設 G:),鏡像模式在使用者資料夾裡
    $roots = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root })
    if ($env:USERPROFILE) { $roots += $env:USERPROFILE }
    foreach ($root in $roots) {
        foreach ($name in $DriveFolderNames) {
            $p = Join-Path $root $name
            if (Test-Path -LiteralPath $p -PathType Container) { return (Join-Path $p $BackupFolderName) }
        }
    }
    throw "找不到 Google 雲端硬碟的「我的雲端硬碟」資料夾。請確認已經安裝並登入 Google 雲端硬碟電腦版;或用 -Destination 指定備份資料夾,例如 -Destination 'G:\我的雲端硬碟\$BackupFolderName'"
}

# 使用者資料夾裡的檔案(不含子資料夾):檔名 -> 內容
function Get-UserFiles {
    if (-not (Test-Path -LiteralPath $UserDir -PathType Container)) {
        throw "找不到小麥注音的使用者資料夾 $UserDir"
    }
    $files = [ordered]@{}
    foreach ($f in @(Get-ChildItem -LiteralPath $UserDir -File | Sort-Object Name)) {
        $files[$f.Name] = Read-Bytes $f.FullName
    }
    if ($files.Count -eq 0) { throw "$UserDir 裡沒有檔案" }
    return $files
}

function Test-SameAsSnapshot([string]$SnapshotDir, $Files) {
    $old = @(Get-ChildItem -LiteralPath $SnapshotDir -File)
    if ($old.Count -ne $Files.Count) { return $false }
    foreach ($f in $old) {
        if (-not $Files.Contains($f.Name)) { return $false }
        if ((Get-Sha256 (Read-Bytes $f.FullName)) -ne (Get-Sha256 $Files[$f.Name])) { return $false }
    }
    return $true
}

function Invoke-Backup {
    $dest = Find-BackupDestination
    $files = Get-UserFiles
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $latest = @(Get-ChildItem -LiteralPath $dest -Directory | Where-Object { $_.Name -match $SnapshotPattern } | Sort-Object Name) | Select-Object -Last 1
    if ($latest -and (Test-SameAsSnapshot $latest.FullName $files)) {
        $msg = "內容和最近一份備份 $($latest.FullName) 一樣,這次不備份"
        Write-Host $msg -ForegroundColor Green
        Write-Log $msg
        return
    }
    $name = Get-Date -Format 'yyyyMMdd-HHmmss'
    $snapshot = Join-Path $dest $name
    $n = 2
    while (Test-Path -LiteralPath $snapshot) {
        $snapshot = Join-Path $dest "$name-$n"
        $n++
    }
    New-Item -ItemType Directory -Path $snapshot | Out-Null
    foreach ($key in $files.Keys) {
        [IO.File]::WriteAllBytes((Join-Path $snapshot $key), $files[$key])
    }
    $msg = "已備份 $($files.Count) 個檔案到 ${snapshot}:$(@($files.Keys) -join '、')"
    Write-Host $msg -ForegroundColor Green
    Write-Log $msg
}

# 給工作排程的參數加上引號。結尾的 \ 會把後面的引號跳脫掉,所以去掉
function Format-Argument([string]$Path) {
    $p = $Path.TrimEnd('\')
    if ($p -match '^[A-Za-z]:$') { $p += '\.' }
    return "`"$p`""
}

function Invoke-Register {
    # 先備份一次,確定備份資料夾找得到、寫得進去,才建立排程
    Invoke-Backup
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $scriptCopy = Join-Path $InstallDir 'backup-phrases.ps1'
    if ($PSCommandPath -ne $scriptCopy) { Copy-Item -LiteralPath $PSCommandPath -Destination $scriptCopy -Force }
    $arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $(Format-Argument $scriptCopy)"
    # 排程執行時的目前資料夾不一樣,相對路徑要先換成完整路徑
    $paths = $ExecutionContext.SessionState.Path
    if ($Destination) { $arguments += " -Destination $(Format-Argument $paths.GetUnresolvedProviderPathFromPSPath($Destination))" }
    if ($UserDirGiven) { $arguments += " -UserDir $(Format-Argument $paths.GetUnresolvedProviderPathFromPSPath($UserDir))" }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -Daily -At '12:00'
    # 12:00 電腦沒開的話,下次開機登入後補跑
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force `
        -Description '把小麥注音的使用者檔備份到 Google 雲端硬碟。本 fork 的 my-scripts/backup-phrases.ps1 建立,說明見 MY-SETUP.md。' | Out-Null
    Write-Host "已建立工作排程「$TaskName」:每天 12:00 備份一次(那時沒開機的話,開機登入後補跑)。" -ForegroundColor Green
    Write-Host "排程執行的是 $scriptCopy,紀錄寫在 $LogPath。"
    Write-Log "建立工作排程「$TaskName」"
}

function Invoke-Unregister {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "已刪除工作排程「$TaskName」。雲端硬碟上的備份都還在。" -ForegroundColor Green
        Write-Log "刪除工作排程「$TaskName」"
    } else {
        Write-Host "沒有「$TaskName」這個工作排程,不用刪除。"
    }
}

function Invoke-Restore {
    if (-not (Test-Path -LiteralPath $Restore -PathType Container)) { throw "找不到備份資料夾 $Restore" }
    $files = @(Get-ChildItem -LiteralPath $Restore -File | Sort-Object Name)
    if ($files.Count -eq 0) { throw "$Restore 裡沒有檔案" }
    Write-Host "要從 $Restore 還原這些檔案到 ${UserDir}:"
    foreach ($f in $files) { Write-Host "  $($f.Name)" }
    if (-not $Force) {
        $answer = Read-Host '目前的檔案會先備份起來。確定要還原嗎?輸入 Y 再按 Enter'
        if ($answer -ne 'Y' -and $answer -ne 'y') {
            Write-Host '沒有還原。'
            return
        }
    }

    New-Item -ItemType Directory -Force -Path $UserDir | Out-Null
    $current = @(Get-ChildItem -LiteralPath $UserDir -File)
    if ($current.Count -gt 0) {
        $backupDir = Join-Path $UserDir 'backup'
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        foreach ($f in $current) {
            $dest = Join-Path $backupDir ('{0}-{1}-before-restore{2}' -f $f.BaseName, $stamp, $f.Extension)
            [IO.File]::WriteAllBytes($dest, (Read-Bytes $f.FullName))
        }
        Write-Host "目前的 $($current.Count) 個檔案已備份到 $backupDir(檔名有 -$stamp-before-restore)"
    }

    # 小麥注音 Server 會一直開著 user.txt 等檔案,不先暫停的話可能沒辦法覆蓋
    $servers = @(Get-Process -Name 'McBopomofoServer*' -ErrorAction SilentlyContinue)
    $serverPaths = @($servers | ForEach-Object { $_.Path } | Where-Object { $_ } | Select-Object -Unique)
    if ($servers.Count -gt 0) {
        Write-Host '暫停小麥注音 Server……'
        $servers | Stop-Process -Force
        $servers | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    }
    try {
        foreach ($f in $files) {
            [IO.File]::WriteAllBytes((Join-Path $UserDir $f.Name), (Read-Bytes $f.FullName))
        }
    } finally {
        foreach ($p in $serverPaths) {
            Write-Host '重新啟動小麥注音 Server……'
            Start-Process -FilePath $p
        }
    }
    $msg = "已從 $Restore 還原 $($files.Count) 個檔案"
    Write-Host $msg -ForegroundColor Green
    Write-Log $msg
}

try {
    switch ($PSCmdlet.ParameterSetName) {
        'Register' { Invoke-Register }
        'Unregister' { Invoke-Unregister }
        'Restore' { Invoke-Restore }
        default { Invoke-Backup }
    }
    exit 0
} catch {
    Write-Host "錯誤:$($_.Exception.Message)" -ForegroundColor Red
    Write-Log "錯誤:$($_.Exception.Message)"
    exit 1
}
