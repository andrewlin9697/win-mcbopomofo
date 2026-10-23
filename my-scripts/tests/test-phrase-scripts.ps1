# 本 fork 自己加的測試(不是官方檔案):測試 my-scripts/install-phrases.ps1 和 my-scripts/backup-phrases.ps1。
# CI(「測試詞庫腳本」)在 Windows 上用 PowerShell 5.1 和 7 各跑一次。也可以在本機跑:
#   powershell -NoProfile -ExecutionPolicy Bypass -File my-scripts\tests\test-phrase-scripts.ps1
# 只在暫存資料夾裡操作,不會碰到真正的 %APPDATA%\WinMcBopomofo。
# 有設定 TEST_DOWNLOAD_REPO 和 TEST_DOWNLOAD_REF 時,另外測試從 GitHub 下載腳本和詞庫。
# 在 GitHub Actions 上另外測試自動找雲端硬碟資料夾、建立和刪除工作排程。

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot)
$install = Join-Path $root 'my-scripts/install-phrases.ps1'
$backup = Join-Path $root 'my-scripts/backup-phrases.ps1'
$phrasesDir = Join-Path $root 'my-phrases'
$ps = (Get-Process -Id $PID).Path
$onWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'
$inCI = [bool]$env:GITHUB_ACTIONS
$utf8 = New-Object System.Text.UTF8Encoding($false)
$work = Join-Path ([IO.Path]::GetTempPath()) ("phrase-scripts-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$script:failures = 0
# 讓子程序的中文輸出在 CI 紀錄裡不會變成問號(沒有主控台時會失敗,不影響測試)
try { [Console]::OutputEncoding = $utf8 } catch { }

function Check([bool]$Condition, [string]$Name) {
    if ($Condition) {
        Write-Host "  ok    $Name"
    } else {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        $script:failures++
    }
}

function Run([string]$Script, [string[]]$Arguments) {
    # PowerShell 5.1 在 Stop 模式下,子程序寫到 stderr 會直接中斷
    $ErrorActionPreference = 'Continue'
    $out = & $ps -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host ($out.TrimEnd() -replace '(?m)^', '        | ')
    return $code
}

function New-Dir([string]$Name) {
    $d = Join-Path $work $Name
    New-Item -ItemType Directory -Path $d | Out-Null
    return $d
}

function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllBytes($Path, $utf8.GetBytes($Text)) }

function Same-Bytes([byte[]]$A, [byte[]]$B) { [Convert]::ToBase64String($A) -eq [Convert]::ToBase64String($B) }

function Starts-With([byte[]]$All, [byte[]]$Prefix) {
    $All.Length -ge $Prefix.Length -and ([Convert]::ToBase64String($All, 0, $Prefix.Length) -eq [Convert]::ToBase64String($Prefix))
}

# 「詞 注音」-> 出現次數
function Count-Phrases([string]$Path) {
    $counts = @{}
    foreach ($line in $utf8.GetString([IO.File]::ReadAllBytes($Path)).Split("`n")) {
        $t = $line.Trim(" `t`r$([char]0xFEFF)".ToCharArray())
        if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
        $f = $t -split '[ \t]+'
        $key = $f[0] + ' ' + $f[1]
        if ($counts.ContainsKey($key)) { $counts[$key]++ } else { $counts[$key] = 1 }
    }
    return $counts
}

# my-phrases 裡所有的「詞 注音」
$expected = New-Object 'System.Collections.Generic.List[string]'
foreach ($f in @(Get-ChildItem -LiteralPath $phrasesDir -Filter '*.txt' -File | Sort-Object Name)) {
    foreach ($line in $utf8.GetString([IO.File]::ReadAllBytes($f.FullName)).Split("`n")) {
        $t = $line.Trim()
        if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
        $f2 = $t -split '\s+'
        $expected.Add($f2[0] + ' ' + $f2[1])
    }
}
Write-Host "PowerShell $($PSVersionTable.PSVersion)($ps),my-phrases 共 $($expected.Count) 行"
$first, $second, $third = $expected[0], $expected[1], $expected[2]

function Check-AllPresent([string]$UserTxt, [string[]]$Except) {
    $counts = Count-Phrases $UserTxt
    $bad = @($expected | Where-Object { $Except -notcontains $_ -and (-not $counts.ContainsKey($_) -or $counts[$_] -ne 1) })
    Check ($bad.Count -eq 0) "my-phrases 的每一行剛好出現一次(有問題的:$($bad.Count) 行)"
    foreach ($e in $Except) { Check (-not $counts.ContainsKey($e)) "沒有加入 $e" }
}

try {
    # ================= install-phrases.ps1 =================
    Write-Host "`n[install] 合併進現有的 user.txt(CRLF、有自己加的詞、exclude.txt)"
    $u = New-Dir 'install-existing'
    $userTxt = Join-Path $u 'user.txt'
    $secondValue = $second.Split(' ')[0]
    $original = "# McBopomofo User Phrases`r`n" +
        "測試詞 ㄘㄜˋ-ㄕˋ-ㄘˊ`r`n" +
        ($first.Replace(' ', "`t") + "  `r`n") +           # 已經有了,只是分隔和空白不一樣
        "$secondValue ㄅㄚ`r`n" +                            # 同一個詞、不同讀音,不算重複
        "# 自己的註解`r`n" +
        "最後一個 ㄗㄨㄟˋ-ㄏㄡˋ-ㄧˊ-ㄍㄜˋ`r`n"
    Write-Text $userTxt $original
    Write-Text (Join-Path $u 'exclude.txt') "# McBopomofo Excluded Phrases`r`n$third`r`n"
    Write-Text (Join-Path $u 'mcbopomofo.ini') "[General]`r`nSomething=1`r`n"
    $origBytes = [IO.File]::ReadAllBytes($userTxt)

    $code = Run $install @('-PhrasesDir', $phrasesDir, '-UserDir', $u)
    Check ($code -eq 0) "結束代碼 0(實際 $code)"
    $afterBytes = [IO.File]::ReadAllBytes($userTxt)
    Check (Starts-With $afterBytes $origBytes) '原本的內容一個位元組都沒變'
    Check-AllPresent $userTxt @($third)
    $counts = Count-Phrases $userTxt
    Check ($counts.ContainsKey("$secondValue ㄅㄚ") -and $counts.ContainsKey($second)) '同一個詞的兩種讀音都在'
    $appended = $utf8.GetString($afterBytes, $origBytes.Length, $afterBytes.Length - $origBytes.Length)
    Check (($appended -replace "`r`n", '') -notmatch "[`r`n]") '新增的部分用 CRLF 換行'
    Check ($appended.StartsWith('# 下面 ')) '新增的部分開頭有註解'
    $backups = @(Get-ChildItem -LiteralPath (Join-Path $u 'backup') -File)
    Check ($backups.Count -eq 3) "備份了 3 個檔案(實際 $($backups.Count))"
    $userBackup = @($backups | Where-Object { $_.Name -match '^user-\d{8}-\d{6}\.txt$' })
    Check ($userBackup.Count -eq 1 -and (Same-Bytes ([IO.File]::ReadAllBytes($userBackup[0].FullName)) $origBytes)) 'user.txt 的備份檔名帶時間、內容和原本一樣'
    Check (@($backups | Where-Object { $_.Name -match '^exclude-\d{8}-\d{6}\.txt$' }).Count -eq 1) 'exclude.txt 有備份'
    Check (@($backups | Where-Object { $_.Name -match '^mcbopomofo-\d{8}-\d{6}\.ini$' }).Count -eq 1) 'mcbopomofo.ini 有備份'

    Write-Host "`n[install] 再執行一次:不應該有任何變更"
    $mtime = (Get-Item -LiteralPath $userTxt).LastWriteTimeUtc
    Start-Sleep -Seconds 1
    $code = Run $install @('-PhrasesDir', $phrasesDir, '-UserDir', $u)
    Check ($code -eq 0) "結束代碼 0(實際 $code)"
    Check (Same-Bytes ([IO.File]::ReadAllBytes($userTxt)) $afterBytes) 'user.txt 內容沒變'
    Check ((Get-Item -LiteralPath $userTxt).LastWriteTimeUtc -eq $mtime) 'user.txt 修改時間沒變(小麥注音不會重新載入)'

    Write-Host "`n[install] 使用者資料夾和 user.txt 都不存在(不指定 -PhrasesDir,用 repo 裡的 my-phrases)"
    $u = Join-Path $work 'install-new'
    $code = Run $install @('-UserDir', $u)
    Check ($code -eq 0) "結束代碼 0(實際 $code)"
    $userTxt = Join-Path $u 'user.txt'
    Check (Starts-With ([IO.File]::ReadAllBytes($userTxt)) $utf8.GetBytes("# McBopomofo User Phrases`r`n")) '用小麥注音的檔頭建立'
    Check-AllPresent $userTxt @()
    Check (-not (Test-Path -LiteralPath (Join-Path $u 'backup'))) '沒有東西要備份'

    Write-Host "`n[install] 有 BOM、只用 LF、最後一行沒有換行"
    $u = New-Dir 'install-lf'
    $userTxt = Join-Path $u 'user.txt'
    $origBytes = [byte[]]((0xEF, 0xBB, 0xBF) + $utf8.GetBytes("# McBopomofo User Phrases`n測試詞 ㄘㄜˋ-ㄕˋ-ㄘˊ"))
    [IO.File]::WriteAllBytes($userTxt, $origBytes)
    $code = Run $install @('-PhrasesDir', $phrasesDir, '-UserDir', $u)
    Check ($code -eq 0) "結束代碼 0(實際 $code)"
    $afterBytes = [IO.File]::ReadAllBytes($userTxt)
    Check (Starts-With $afterBytes $origBytes) '原本的內容(含 BOM)沒變'
    Check ($afterBytes[$origBytes.Length] -eq 10) '先補上換行'
    Check (-not ($afterBytes -contains 13)) '新增的部分用 LF 換行'
    Check-AllPresent $userTxt @()

    Write-Host "`n[install] user.txt 不是 UTF-8:不能動它"
    $u = New-Dir 'install-big5'
    $userTxt = Join-Path $u 'user.txt'
    $origBytes = [byte[]]($utf8.GetBytes("# McBopomofo User Phrases`r`n") + (0xB4, 0xFA, 0xB8, 0xD5, 0x20, 0x41, 0x0D, 0x0A))
    [IO.File]::WriteAllBytes($userTxt, $origBytes)
    $code = Run $install @('-PhrasesDir', $phrasesDir, '-UserDir', $u)
    Check ($code -eq 1) "結束代碼 1(實際 $code)"
    Check (Same-Bytes ([IO.File]::ReadAllBytes($userTxt)) $origBytes) 'user.txt 沒有被修改'

    if ($env:TEST_DOWNLOAD_REPO -and $env:TEST_DOWNLOAD_REF) {
        Write-Host "`n[install] 照說明文件的方式:從 GitHub 下載腳本到暫存資料夾執行,詞庫也從 GitHub 下載"
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $dl = New-Dir 'download'
        $f = Join-Path $dl 'install-phrases.ps1'
        Invoke-WebRequest "https://raw.githubusercontent.com/$($env:TEST_DOWNLOAD_REPO)/$($env:TEST_DOWNLOAD_REF)/my-scripts/install-phrases.ps1" -OutFile $f -UseBasicParsing
        Check (Same-Bytes ([IO.File]::ReadAllBytes($f)) ([IO.File]::ReadAllBytes($install))) '下載的腳本和 repo 裡的一樣(含 BOM)'
        $u = Join-Path $work 'install-download'
        $code = Run $f @('-UserDir', $u, '-Repo', $env:TEST_DOWNLOAD_REPO, '-Ref', $env:TEST_DOWNLOAD_REF)
        Check ($code -eq 0) "結束代碼 0(實際 $code)"
        Check-AllPresent (Join-Path $u 'user.txt') @()
    }

    # ================= backup-phrases.ps1 =================
    Write-Host "`n[backup] 備份到指定資料夾"
    $u = New-Dir 'backup-user'
    $dest = Join-Path $work 'backup-dest'
    $original = "# McBopomofo User Phrases`r`n測試詞 ㄘㄜˋ-ㄕˋ-ㄘˊ`r`n"
    Write-Text (Join-Path $u 'user.txt') $original
    Write-Text (Join-Path $u 'exclude.txt') "# McBopomofo Excluded Phrases`r`n"
    Write-Text (Join-Path $u 'mcbopomofo.ini') "[General]`r`nSomething=1`r`n"
    New-Item -ItemType Directory -Path (Join-Path $u 'backup') | Out-Null
    Write-Text (Join-Path $u 'backup/user-20260101-000000.txt') 'old'
    $code = Run $backup @('-Destination', $dest, '-UserDir', $u)
    Check ($code -eq 0) "結束代碼 0(實際 $code)"
    $snaps = @(Get-ChildItem -LiteralPath $dest -Directory)
    Check ($snaps.Count -eq 1 -and $snaps[0].Name -match '^\d{8}-\d{6}$') "建立一份以時間命名的備份($(@($snaps | ForEach-Object Name) -join ', '))"
    $firstSnap = $snaps[0].FullName
    $names = @(Get-ChildItem -LiteralPath $firstSnap -Force | ForEach-Object Name | Sort-Object)
    Check (($names -join ',') -eq 'exclude.txt,mcbopomofo.ini,user.txt') "只備份使用者資料夾裡的檔案,不含 backup\ 子資料夾($($names -join ','))"
    Check (Same-Bytes ([IO.File]::ReadAllBytes((Join-Path $firstSnap 'user.txt'))) $utf8.GetBytes($original)) 'user.txt 內容一樣'

    Write-Host "`n[backup] 內容沒變:不再備份"
    $code = Run $backup @('-Destination', $dest, '-UserDir', $u)
    Check ($code -eq 0) "結束代碼 0(實際 $code)"
    Check (@(Get-ChildItem -LiteralPath $dest -Directory).Count -eq 1) '還是只有一份備份'

    Write-Host "`n[backup] user.txt 變了:多一份,舊的不動"
    Write-Text (Join-Path $u 'user.txt') ($original + "新的詞 ㄒㄧㄣ-ㄉㄜ˙-ㄘˊ`r`n")
    $code = Run $backup @('-Destination', $dest, '-UserDir', $u)
    Check ($code -eq 0) "結束代碼 0(實際 $code)"
    Check (@(Get-ChildItem -LiteralPath $dest -Directory).Count -eq 2) '變成兩份備份'
    Check (Same-Bytes ([IO.File]::ReadAllBytes((Join-Path $firstSnap 'user.txt'))) $utf8.GetBytes($original)) '第一份備份沒有被改'

    Write-Host "`n[backup] 從第一份備份還原"
    Write-Text (Join-Path $u 'phrases-replacement.txt') "測試 測驗`r`n"
    $code = Run $backup @('-Restore', $firstSnap, '-Force', '-UserDir', $u)
    Check ($code -eq 0) "結束代碼 0(實際 $code)"
    Check (Same-Bytes ([IO.File]::ReadAllBytes((Join-Path $u 'user.txt'))) $utf8.GetBytes($original)) 'user.txt 還原成第一份備份'
    Check (Test-Path -LiteralPath (Join-Path $u 'phrases-replacement.txt')) '備份裡沒有的檔案沒有被刪掉'
    Check (@(Get-ChildItem -LiteralPath (Join-Path $u 'backup') -File | Where-Object { $_.Name -match '^user-\d{8}-\d{6}-before-restore\.txt$' }).Count -eq 1) '還原前先備份了目前的 user.txt'

    Write-Host "`n[backup] 備份資料夾不存在時還原:失敗而且不動任何檔案"
    $before = [IO.File]::ReadAllBytes((Join-Path $u 'user.txt'))
    $code = Run $backup @('-Restore', (Join-Path $work 'no-such-folder'), '-Force', '-UserDir', $u)
    Check ($code -eq 1) "結束代碼 1(實際 $code)"
    Check (Same-Bytes ([IO.File]::ReadAllBytes((Join-Path $u 'user.txt'))) $before) 'user.txt 沒變'

    if ($onWindows -and $inCI) {
        Write-Host "`n[backup] 自動找雲端硬碟資料夾(在 CI 上暫時建立 %USERPROFILE%\My Drive)"
        $drive = Join-Path $env:USERPROFILE 'My Drive'
        if (Test-Path -LiteralPath $drive) { throw "$drive 已經存在,不在這台機器上測試" }
        New-Item -ItemType Directory -Path $drive | Out-Null
        try {
            $code = Run $backup @('-UserDir', $u)
            Check ($code -eq 0) "結束代碼 0(實際 $code)"
            Check (@(Get-ChildItem -LiteralPath (Join-Path $drive '小麥注音備份') -Directory).Count -eq 1) '備份到 My Drive\小麥注音備份'
        } finally {
            Remove-Item -LiteralPath $drive -Recurse -Force
        }

        Write-Host "`n[backup] 建立和刪除工作排程"
        $taskName = '小麥注音雲端備份'
        $dest2 = Join-Path $work 'backup-dest-task'
        $code = Run $backup @('-Register', '-Destination', $dest2, '-UserDir', $u)
        Check ($code -eq 0) "結束代碼 0(實際 $code)"
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Check ($null -ne $task) '工作排程建立了'
        if ($task) {
            $action = @($task.Actions)[0]
            Write-Host "        | $($action.Execute) $($action.Arguments)"
            Check (@(Get-ChildItem -LiteralPath $dest2 -Directory).Count -eq 1) '建立排程前先備份了一次'
            # 用排程裡的指令實際跑一次,確認引號沒有問題
            $log = Join-Path $work 'task-output.txt'
            $p = Start-Process -FilePath $action.Execute -ArgumentList $action.Arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $log
            Write-Host ((Get-Content -LiteralPath $log -Raw -Encoding UTF8) -replace '(?m)^', '        | ')
            Check ($p.ExitCode -eq 0) "排程的指令可以執行(結束代碼 $($p.ExitCode))"
        }
        $code = Run $backup @('-Unregister')
        Check ($code -eq 0) "結束代碼 0(實際 $code)"
        Check ($null -eq (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) '工作排程刪掉了'
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failures -gt 0) {
    Write-Host "`n$($script:failures) 項檢查失敗" -ForegroundColor Red
    exit 1
}
Write-Host "`n全部通過" -ForegroundColor Green
exit 0
