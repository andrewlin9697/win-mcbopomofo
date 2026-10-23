<#
.SYNOPSIS
把本 fork 的自訂詞庫(my-phrases/*.txt)合併進小麥注音的使用者詞庫 user.txt。

.DESCRIPTION
本 fork 自己加的腳本(不是官方檔案),說明見 MY-SETUP.md。Windows 內建的 PowerShell 5.1 就能執行,不需要系統管理員。

1. 先把 %APPDATA%\WinMcBopomofo 裡的檔案(user.txt、exclude.txt、mcbopomofo.ini 等,不含子資料夾)
   複製一份到同資料夾的 backup\,檔名加上時間,例如 user-20261023-153012.txt。
2. 只在 user.txt 最後面新增缺少的詞(詞和注音都相同才算已經有),原本的每一行都不刪、不改、不換順序。
   exclude.txt 裡有的詞(在小麥注音裡刪掉的詞)不會加回去。
3. user.txt 不存在時,用小麥注音自己建立時的檔頭建立。

小麥注音靠檔案修改時間發現 user.txt 變了,會自己重新載入,不用重開。

.PARAMETER PhrasesDir
詞庫資料夾。沒指定時:這個腳本放在 repo 的 my-scripts\ 裡(例如下載整個 repo 的 ZIP),就用旁邊的 my-phrases\;
否則從 GitHub 下載 my-phrases\。

.PARAMETER UserDir
小麥注音的使用者資料夾,預設 %APPDATA%\WinMcBopomofo。

.PARAMETER Repo
從 GitHub 下載詞庫時用的 repo。

.PARAMETER Ref
從 GitHub 下載詞庫時用的分支或 commit。
#>
[CmdletBinding()]
param(
    [string]$PhrasesDir,
    [string]$UserDir = (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'WinMcBopomofo'),
    [string]$Repo = 'andrewlin9697/win-mcbopomofo',
    [string]$Ref = 'main'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 和小麥注音建立 user.txt 時寫的一樣(src/Server/main.cpp 的 userPhraseFileHeader;Windows 上換行是 CRLF)
$UserPhraseFileHeader = "# McBopomofo User Phrases`r`n"
$StrictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$TrimChars = " `t`r$([char]0xFEFF)".ToCharArray()

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

# 和引擎一樣:去掉前後空白後,空行和 # 開頭的行略過,第一欄是詞、第二欄是注音
function ConvertFrom-PhraseText([string]$Text) {
    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($line in $Text.Split("`n")) {
        $t = $line.Trim($TrimChars)
        if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
        $fields = $t -split '[ \t]+'
        if ($fields.Count -lt 2) { continue }
        $list.Add([pscustomobject]@{ Value = $fields[0]; Reading = $fields[1]; Key = $fields[0] + ' ' + $fields[1] })
    }
    return , $list
}

function Get-LocalPhraseFiles([string]$Dir) {
    Get-ChildItem -LiteralPath $Dir -Filter '*.txt' -File | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Bytes = [IO.File]::ReadAllBytes($_.FullName) }
    }
}

function Get-RemotePhraseFiles {
    # 舊版 Windows 的 PowerShell 5.1 預設可能沒開 TLS 1.2,GitHub 需要
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $headers = @{}
    # 只有 CI 測試會設定,避免 GitHub API 未登入的次數限制
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
    $items = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/contents/my-phrases?ref=$Ref" -Headers $headers -UseBasicParsing
    $client = New-Object System.Net.WebClient
    try {
        foreach ($item in @($items | Where-Object { $_.type -eq 'file' -and $_.name -like '*.txt' } | Sort-Object name)) {
            [pscustomobject]@{ Name = $item.name; Bytes = $client.DownloadData($item.download_url) }
        }
    } finally {
        $client.Dispose()
    }
}

# 把資料夾裡的檔案(不含子資料夾)複製到 backup\,檔名加上時間。回傳備份了哪些檔案
function Backup-UserFiles([string]$Dir, [string]$Stamp) {
    $files = @(Get-ChildItem -LiteralPath $Dir -File)
    if ($files.Count -eq 0) { return @() }
    $backupDir = Join-Path $Dir 'backup'
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    foreach ($f in $files) {
        $dest = Join-Path $backupDir ('{0}-{1}{2}' -f $f.BaseName, $Stamp, $f.Extension)
        $n = 2
        while (Test-Path -LiteralPath $dest) {
            $dest = Join-Path $backupDir ('{0}-{1}-{2}{3}' -f $f.BaseName, $Stamp, $n, $f.Extension)
            $n++
        }
        [IO.File]::WriteAllBytes($dest, (Read-Bytes $f.FullName))
        $dest
    }
}

try {
    # ---- 讀自訂詞庫 ----
    if ($PhrasesDir) {
        $source = "資料夾 $PhrasesDir"
        $phraseFiles = @(Get-LocalPhraseFiles $PhrasesDir)
    } elseif ((Test-Path -LiteralPath (Join-Path $PSScriptRoot 'check_phrases.py')) -and
              (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\my-phrases') -PathType Container)) {
        $PhrasesDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\my-phrases')).Path
        $source = "資料夾 $PhrasesDir"
        $phraseFiles = @(Get-LocalPhraseFiles $PhrasesDir)
    } else {
        $source = "GitHub $Repo($Ref)的 my-phrases/"
        Write-Host "從 $source 下載詞庫……"
        try {
            $phraseFiles = @(Get-RemotePhraseFiles)
        } catch {
            throw "下載詞庫失敗:$($_.Exception.Message)`n請確認網路連線;或下載整個 repo 的 ZIP,解壓縮後執行裡面的 my-scripts\install-phrases.ps1。"
        }
    }
    if ($phraseFiles.Count -eq 0) { throw "在 $source 找不到任何 .txt 詞庫檔" }

    $phrases = New-Object 'System.Collections.Generic.List[object]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($pf in $phraseFiles) {
        try {
            $text = $StrictUtf8.GetString($pf.Bytes)
        } catch {
            throw "詞庫檔 $($pf.Name) 不是 UTF-8 編碼"
        }
        foreach ($p in (ConvertFrom-PhraseText $text)) {
            if ($seen.Add($p.Key)) { $phrases.Add($p) }
        }
    }
    if ($phrases.Count -eq 0) { throw "在 $source 的詞庫檔裡沒有讀到任何詞" }
    Write-Host "自訂詞庫:$source,$($phraseFiles.Count) 個檔案,共 $($phrases.Count) 行(詞 + 注音)"

    # ---- 備份 ----
    if (-not (Test-Path -LiteralPath $UserDir -PathType Container)) {
        Write-Host "找不到 $UserDir(小麥注音可能還沒執行過),先建立這個資料夾"
        New-Item -ItemType Directory -Force -Path $UserDir | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backups = @(Backup-UserFiles $UserDir $stamp)
    if ($backups.Count -gt 0) {
        Write-Host "已備份 $($backups.Count) 個檔案到 $(Join-Path $UserDir 'backup'):"
        foreach ($b in $backups) { Write-Host "  $(Split-Path -Leaf $b)" }
    } else {
        Write-Host '使用者資料夾裡沒有檔案,不用備份'
    }

    # ---- 讀 user.txt 和 exclude.txt ----
    $userTxt = Join-Path $UserDir 'user.txt'
    $excludeTxt = Join-Path $UserDir 'exclude.txt'
    $created = $false
    if (-not (Test-Path -LiteralPath $userTxt -PathType Leaf)) {
        # 小麥注音只有在 user.txt 存在時才會把打字時加的詞寫進去
        [IO.File]::WriteAllBytes($userTxt, $StrictUtf8.GetBytes($UserPhraseFileHeader))
        $created = $true
        Write-Host '找不到 user.txt,用小麥注音的檔頭建立了一個'
    }
    $before = Read-Bytes $userTxt
    try {
        $userText = $StrictUtf8.GetString($before)
    } catch {
        throw "user.txt 不是 UTF-8 編碼,為了不弄壞它,沒有做任何修改。請用記事本開啟 $userTxt,另存新檔時編碼選「UTF-8」再執行一次。"
    }
    $existing = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($p in (ConvertFrom-PhraseText $userText)) { [void]$existing.Add($p.Key) }
    $excluded = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    if (Test-Path -LiteralPath $excludeTxt -PathType Leaf) {
        foreach ($p in (ConvertFrom-PhraseText ([Text.Encoding]::UTF8.GetString((Read-Bytes $excludeTxt))))) { [void]$excluded.Add($p.Key) }
    }

    $toAdd = @($phrases | Where-Object { -not $existing.Contains($_.Key) -and -not $excluded.Contains($_.Key) })
    $skippedExcluded = @($phrases | Where-Object { -not $existing.Contains($_.Key) -and $excluded.Contains($_.Key) })
    $already = $phrases.Count - $toAdd.Count - $skippedExcluded.Count

    Write-Host "已經在 user.txt 裡:$already 行"
    if ($skippedExcluded.Count -gt 0) {
        Write-Host "在 exclude.txt 裡(你在小麥注音刪掉的詞),不加回去:$($skippedExcluded.Count) 行"
        foreach ($p in $skippedExcluded) { Write-Host "  $($p.Key)" }
    }
    if ($toAdd.Count -eq 0) {
        Write-Host '沒有要新增的詞,user.txt 沒有變更。' -ForegroundColor Green
        exit 0
    }

    # ---- 加到 user.txt 最後面 ----
    # 換行跟著檔案原本的樣子;小麥注音在 Windows 上寫的是 CRLF
    $nl = if ($userText.Contains("`n") -and -not $userText.Contains("`r`n")) { "`n" } else { "`r`n" }
    $sb = New-Object System.Text.StringBuilder
    if ($before.Length -gt 0 -and $before[$before.Length - 1] -ne 10) { [void]$sb.Append($nl) }
    [void]$sb.Append("# 下面 $($toAdd.Count) 行由 my-scripts/install-phrases.ps1 從 my-phrases/ 加入($(Get-Date -Format 'yyyy-MM-dd HH:mm'))$nl")
    foreach ($p in $toAdd) { [void]$sb.Append($p.Key + $nl) }
    $appendBytes = $StrictUtf8.GetBytes($sb.ToString())
    $fs = [IO.File]::Open($userTxt, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try {
        $fs.Write($appendBytes, 0, $appendBytes.Length)
    } finally {
        $fs.Dispose()
    }

    # ---- 確認原本的內容一個位元組都沒變,而且新增的詞都在 ----
    $after = Read-Bytes $userTxt
    $prefixSame = $after.Length -ge $before.Length -and
        ([Convert]::ToBase64String($after, 0, $before.Length) -eq [Convert]::ToBase64String($before))
    $afterKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($p in (ConvertFrom-PhraseText $StrictUtf8.GetString($after))) { [void]$afterKeys.Add($p.Key) }
    $missing = @($toAdd | Where-Object { -not $afterKeys.Contains($_.Key) })
    if (-not $prefixSame -or $missing.Count -gt 0) {
        throw "寫入後檢查不通過(原本內容沒變:$prefixSame,沒寫進去的詞:$($missing.Count) 個)。備份在 $(Join-Path $UserDir 'backup')。"
    }

    if ($created) {
        Write-Host "已新增 $($toAdd.Count) 行到新建立的 user.txt。" -ForegroundColor Green
    } else {
        Write-Host "已新增 $($toAdd.Count) 行到 user.txt 最後面,原本的內容沒有變動。" -ForegroundColor Green
    }
    Write-Host '小麥注音會自動重新載入,不用重開。'
    exit 0
} catch {
    Write-Host "錯誤:$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
