# 我的 fork 說明

這個 repo fork 自官方的 [openvanilla/win-mcbopomofo](https://github.com/openvanilla/win-mcbopomofo)(小麥注音 Windows 版)。
官方不發行安裝檔,所以這裡用 GitHub Actions 自己編譯,把安裝檔放在 [Releases](https://github.com/andrewlin9697/win-mcbopomofo/releases)。

- 官方原有的檔案一律不改,本 fork 只會新增自己的檔案:`.github/workflows/my-*.yml`、`my-phrases/`、`my-scripts/`、`MY-SETUP.md`。
- 這裡編出來的是**非官方**、**沒有數位簽章**的安裝檔。
- 不要對官方 repo 開 PR 或 issue(官方也寫明不收)。在 repo 頁面看到 **Contribute → Open pull request** 時不要按。

內容:[下載與安裝](#下載與安裝)、[自訂詞庫](#自訂詞庫裝進小麥注音)、[備份到 Google 雲端硬碟](#備份到-google-雲端硬碟)、[小麥注音使用小抄](#小麥注音使用小抄)、[自動流程](#自動流程)、[出問題時怎麼知道](#出問題時怎麼知道)、[手動操作](#手動操作)、[排程被停用](#排程被停用)

## 下載與安裝

1. 打開 [最新版 Release](https://github.com/andrewlin9697/win-mcbopomofo/releases/latest),下載 `Win-McBopomofo-Installer.msi`。x64、x86、ARM64 都包在同一個安裝檔裡。
2. (建議)核對檔案沒被動過:在下載資料夾按右鍵 → 在終端機中開啟,執行
   ```powershell
   (Get-FileHash .\Win-McBopomofo-Installer.msi -Algorithm SHA256).Hash
   ```
   印出來的值要和 Release 頁上寫的 SHA256 一樣(大小寫不用管)。
3. 執行 `.msi`。因為沒有簽章,Windows 可能跳出「Windows 已保護您的電腦」,按「其他資訊」→「仍要執行」。

版本名稱看得出對應官方哪個 commit,例如 `upstream-2026.10.09-978b39d` 就是官方 2026-10-09(台灣時間)的 commit `978b39d`。

## 自訂詞庫:裝進小麥注音

`my-phrases/` 裡的詞(說明見 [my-phrases/README.md](my-phrases/README.md))要合併進小麥注音的使用者詞庫 `user.txt` 才會生效。用 `my-scripts/install-phrases.ps1`,第一次安裝和之後詞庫有更新時都是同一個做法:

1. 先裝好小麥注音,用它打過一次字(它會建立使用者資料夾 `%APPDATA%\WinMcBopomofo`)。
2. 按開始 → 輸入 `PowerShell` → 開啟「Windows PowerShell」(不用系統管理員)。
3. 把下面三行一起貼上,按 Enter:

   ```powershell
   [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
   iwr https://raw.githubusercontent.com/andrewlin9697/win-mcbopomofo/main/my-scripts/install-phrases.ps1 -OutFile $env:TEMP\install-phrases.ps1 -UseBasicParsing
   powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\install-phrases.ps1
   ```

   第一行讓舊版 Windows 也連得上 GitHub,第二行下載腳本,第三行執行。`-ExecutionPolicy Bypass` 只對這一次有效,不會改電腦的設定。

它會依序做這些事:

1. **先備份**:把 `%APPDATA%\WinMcBopomofo` 裡的檔案(`user.txt`、`exclude.txt`、`mcbopomofo.ini` 等,不含子資料夾)複製一份到 `%APPDATA%\WinMcBopomofo\backup\`,檔名加上時間,例如 `user-20261023-153012.txt`。
2. 從 GitHub 下載 `main` 的 `my-phrases/*.txt`,**只把 `user.txt` 缺少的詞加到最後面**:詞和注音都一樣才算已經有,同一個詞的另一種讀音會加。原本的每一行(包括打字時自己加的詞)都不刪、不改、不換順序。加的那段開頭有一行註解,寫著哪天加了幾行。
3. `exclude.txt` 裡有的詞(在小麥注音裡刪掉的)不會加回去,會列出來。
4. 沒有 `user.txt` 就用小麥注音自己的檔頭建立一個。(沒有 `user.txt` 時,打字新增的詞不會被存下來。)
5. 寫完再讀一次,確認原本的內容一個位元組都沒變、新增的詞都在。

小麥注音會自己發現 `user.txt` 改了並重新載入,**不用重開**。重複執行沒關係:已經有的詞不會重複加,沒有要加的詞時 `user.txt` 完全不會被動到(但每次執行都會先備份一份)。

- **不想要某個詞**:用小麥注音刪掉(見下面[加詞、刪詞](#加詞刪詞)),它會記在 `exclude.txt`,之後執行也不會再加回來。直接從 `user.txt` 刪掉那一行的話,下次執行會被加回來。
- **想新增詞到 repo**:見 [my-phrases/README.md](my-phrases/README.md) 的「加詞」。PR 合併之後,再執行一次上面的指令。
- **用整個 repo 的 ZIP**:解壓縮後在那個資料夾開 PowerShell,執行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\my-scripts\install-phrases.ps1`,會用 ZIP 裡的 `my-phrases\`,不用連網。
- **出現「user.txt 不是 UTF-8 編碼」**:這時 `user.txt` 沒有被修改。用記事本開啟它,「另存新檔」時編碼選「UTF-8」,再執行一次。
- **要用 `backup\` 裡的檔案還原**:系統匣的小麥注音圖示按右鍵 →「停止 Server」,把要的檔案複製回 `%APPDATA%\WinMcBopomofo`、改回原本的檔名(例如 `user-20261023-153012.txt` 改成 `user.txt`),再登出、重新登入 Windows(小麥注音 Server 會在登入時啟動)。

## 備份到 Google 雲端硬碟

雲端硬碟只拿來備份:把使用者資料夾的檔案單向**複製**過去,不做符號連結、不做雙向同步,也不會從雲端硬碟複製任何東西回來(除非你要[還原](#還原))。用 `my-scripts/backup-phrases.ps1`。

需要先安裝 [Google 雲端硬碟電腦版](https://www.google.com/drive/download/) 並登入。預設的串流模式下,檔案總管裡會有「Google 雲端硬碟 (G:)」,裡面是「我的雲端硬碟」;鏡像模式則是使用者資料夾裡的「我的雲端硬碟」。腳本會自動找這兩個地方(英文介面叫「My Drive」也找得到),備份放在裡面的「小麥注音備份」資料夾。

### 設定每天自動備份(做一次就好)

在 Windows PowerShell(不用系統管理員)貼上:

```powershell
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
iwr https://raw.githubusercontent.com/andrewlin9697/win-mcbopomofo/main/my-scripts/backup-phrases.ps1 -OutFile $env:TEMP\backup-phrases.ps1 -UseBasicParsing
powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\backup-phrases.ps1 -Register
```

它會:

1. 馬上備份一次:把 `%APPDATA%\WinMcBopomofo` 裡的檔案(不含 `backup\` 子資料夾)複製到 `我的雲端硬碟\小麥注音備份\20261023-120000\` 這樣以時間命名的資料夾。
2. 把腳本複製到 `%LOCALAPPDATA%\WinMcBopomofoBackup\`,建立工作排程「小麥注音雲端備份」:每天 12:00 跑一次,那時沒開機的話,開機登入後補跑。執行時可能會閃一下 PowerShell 視窗。

之後每次備份:

- 內容和最近一份備份完全一樣就不再備份,不會每天多一份。
- 舊的備份不會被刪除或修改。檔案很小,不用特別清;想清的話直接在雲端硬碟刪掉舊的資料夾。
- 結果記在 `%LOCALAPPDATA%\WinMcBopomofoBackup\backup.log`。也可以打開「工作排程器」→「工作排程器程式庫」→「小麥注音雲端備份」,看「上次執行結果」(`0x0` 是成功)。
- 雲端硬碟電腦版沒開或沒登入時,那次備份會失敗,紀錄檔會寫原因,隔天會再試。

其他操作(先貼上面前兩行下載腳本,再執行):

| 想做的事 | 第三行改成 |
| --- | --- |
| 手動備份一次 | `powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\backup-phrases.ps1` |
| 停止每天自動備份(雲端硬碟上的備份會留著) | 同上,最後加 ` -Unregister` |
| 備份到別的資料夾 | 同上,最後加 ` -Register -Destination 'D:\某個資料夾'` |

腳本有更新時,重新執行一次 `-Register`,排程才會用到新版(排程執行的是複製到 `%LOCALAPPDATA%` 的那份)。

### 還原

1. 在雲端硬碟的「小麥注音備份」裡找到要還原的那個時間的資料夾,在資料夾上按右鍵 →「複製路徑」。
2. 在 Windows PowerShell 貼上下面三行,但先把最後的 `"G:\我的雲端硬碟\小麥注音備份\20261023-120000"`(含引號)換成剛剛複製的路徑:

   ```powershell
   [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
   iwr https://raw.githubusercontent.com/andrewlin9697/win-mcbopomofo/main/my-scripts/backup-phrases.ps1 -OutFile $env:TEMP\backup-phrases.ps1 -UseBasicParsing
   powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\backup-phrases.ps1 -Restore "G:\我的雲端硬碟\小麥注音備份\20261023-120000"
   ```

3. 確認列出來的檔案,輸入 `Y` 按 Enter。

還原時會先把目前的檔案備份到 `%APPDATA%\WinMcBopomofo\backup\`(檔名有 `-before-restore`),暫停小麥注音 Server(它會一直開著 `user.txt`,不暫停可能沒辦法覆蓋),把備份資料夾裡的檔案複製回 `%APPDATA%\WinMcBopomofo`,再重新啟動 Server。備份裡沒有的檔案不會被刪除。

## 小麥注音使用小抄

### 選單在哪裡

- 系統匣(工作列右下角,可能要先按 `^`)的小麥注音圖示按**右鍵**:「設定」「編輯使用者詞庫」「編輯排除詞庫」「開啟使用者資料夾」,還有「重新啟動 Server」「停止 Server」。
- 打字時,工作列上小麥注音的中/英模式圖示按右鍵,也有「設定」「編輯使用者詞庫」等。
- 設定程式也可以從開始功能表的「小麥注音設定」打開。

### 加詞、刪詞

| 想做的事 | 怎麼按 |
| --- | --- |
| 把打出來的字存成新詞 | 還沒送出前,用 `Shift + ←` / `Shift + →` 選取 2 到 8 個字,看到「按 Enter 加入詞彙」時按 `Enter`。會加到 `user.txt` 最後面 |
| 讓某個詞以後排前面 | 在候選字窗把游標移到那個詞,按 `=`(或 `+`),選「提昇權重」 |
| 刪掉某個詞 | 在候選字窗把游標移到那個詞,按 `-`(或 `_`),選「加入排除字隨」(官方選單上就是這幾個字)。會從 `user.txt` 刪掉並記到 `exclude.txt` |

`=` 和 `-` 只對兩個字以上的詞有用,而且要在「小麥注音」輸入模式(不是「傳統注音」)。

### 常用設定

設定程式「小麥注音偏好設定」裡的選項(文字取自 `src/ConfigApp/McBopomofoConfig.rc`):

| 選項 | 可以選 | 說明 |
| --- | --- | --- |
| 輸入模式 | 小麥注音(自動選字)、傳統注音(手動選字) | 平常用「小麥注音」,會自動選字、可以加詞 |
| 鍵盤佈局 | 標準、倚天、許氏、倚天 26 鍵、漢語拼音、IBM | 一般的注音鍵盤是「標準」 |
| 選字按鍵 | 例如 `123456789`、`asdfghjkl` | 候選字窗裡用哪些鍵選字 |
| 使用空白鍵選取候選字 | 勾、不勾 | 實際作用是「打字中按空白鍵叫出候選字窗」;候選字窗打開之後,空白鍵一律是**翻到下一頁**,不是選字(見 [docs/keyboard-behavior.md](docs/keyboard-behavior.md)) |
| 每頁候選字 | 數字 | 一頁顯示幾個候選字 |
| 選字游標 | 游標前方(像漢音輸入法)、游標後方(像微軟新注音輸入法) | 叫出候選字窗時,要換的是游標前面還是後面的詞。習慣微軟新注音就選「游標後方」 |
| 選字後移動游標 | 勾、不勾 | 選完字後游標要不要移到那個詞後面 |
| 選字窗 | 垂直、水平 | 候選字直排還是橫排 |
| 選字窗字體大小 | 數字 | 候選字窗的字有多大 |
| Shift | 使用 Shift 切換中英文 | 勾了就是按一下 Shift 切換中英文 |
| Esc 鍵 | Esc 清除整個輸入緩衝區 | 勾了按 Esc 會清掉還沒送出的整串字 |

### 使用者資料夾裡的檔案

`%APPDATA%\WinMcBopomofo`(貼到檔案總管的網址列就能打開,或用選單的「開啟使用者資料夾」):

| 檔案 | 內容 |
| --- | --- |
| `user.txt` | 使用者詞庫,一行「詞 注音」(例如 `克希荷夫 ㄎㄜˋ-ㄒㄧ-ㄏㄜˊ-ㄈㄨ`),`#` 開頭是註解。打字時加的詞、安裝腳本加的詞都在這裡 |
| `exclude.txt` | 排除詞庫:刪掉的詞,格式同上 |
| `phrases-replacement.txt` | 進階的詞彙取代,檔案存在才會啟用(預設沒有) |
| `mcbopomofo.ini` | 設定程式存的設定 |
| `disabled-apps.txt` | 不使用小麥注音的程式,一行一個程式名稱 |
| `backup\` | 本 fork 的腳本留下的備份(安裝詞庫前、還原前) |

小麥注音靠檔案修改時間發現 `user.txt`、`exclude.txt` 改了,會自己重新載入。

## 自動流程

| 流程(Actions 頁左邊的名字) | 檔案 | 什麼時候跑 | 做什麼 |
| --- | --- | --- | --- |
| 每週同步官方 | `my-sync.yml` | 每週六台灣時間 09:17;也可以手動執行 | 抓官方 main。沒有新 commit 而且最新版已經發布過 → 什麼都不做。有新 commit → 合併進 main 並推送,接著建置並發布。官方最新版還沒發布 → 補發。 |
| 建置並發布安裝檔 | `my-release.yml` | 手動執行;被「每週同步官方」呼叫;PR 改到 `.github/workflows/my-*.yml` 時 | 在 Windows 上執行 `build_msi.ps1`(Release),發布 Release 並附上 `.msi` 和 `.sha256`。這個官方版本已經發布過就不做事(除非勾選「強制重新發布」)。PR 時只 build、不發布。 |
| Build and Test(官方原有) | `build.yml` | push 到 main、對 main 開 PR 時 | 官方的編譯測試。自動同步推送的 commit 不會觸發它。 |
| 檢查自訂詞庫 | `my-phrases-check.yml` | PR 或 push 到 main 改到 `my-phrases/`、`my-scripts/`、`data/data.txt`、`src/Server/Engine/` 時;也可以手動執行 | 檢查詞庫的格式、讀音、重複,並用小麥注音的引擎實際組字。見 [my-phrases/README.md](my-phrases/README.md)。 |
| 測試詞庫腳本 | `my-scripts-test.yml` | PR 或 push 到 main 改到 `my-scripts/*.ps1`、`my-scripts/tests/` 時;也可以手動執行 | 在 Windows 上用 PowerShell 5.1 和 7 測試安裝詞庫、雲端備份、還原和工作排程(都在暫存資料夾裡,不用真的雲端硬碟)。 |

「每週同步官方」和「建置並發布安裝檔」不會同時跑,後來的會排隊等前一個結束。

GitHub 排程常會晚幾分鐘到幾十分鐘才開始,這是正常的。

## 出問題時怎麼知道

不另外推播。需要你處理的狀況都會讓那次執行在 [Actions](https://github.com/andrewlin9697/win-mcbopomofo/actions) 顯示成紅色(失敗),GitHub 預設會寄失敗通知信給你(設定在 GitHub 右上角頭像 → Settings → Notifications → Actions)。打開那次執行,摘要和紅色的錯誤訊息會寫要做什麼。

新版發布成功不會通知,要看有沒有新版就到 [Releases](https://github.com/andrewlin9697/win-mcbopomofo/releases)。

| 紅色的執行 | 什麼時候 | 我要做什麼 |
| --- | --- | --- |
| 建置並發布安裝檔(或每週同步官方裡的「建置並發布」)失敗 | 編譯或發布失敗 | 通常是官方程式碼或 GitHub 環境的問題。可以等下週自動再試,或之後手動發布一次 |
| 每週同步官方:合併衝突 | 官方的更新和本 fork 的檔案衝突 | main 沒有被改動。需要手動解決衝突(可以請 Claude 幫忙)。**不要**在 Sync fork 按 Discard commits |
| 每週同步官方:需要手動 Sync fork | 官方更新動到 `.github/workflows/`,自動流程沒有權限推送 | 到 repo 頁面按 **Sync fork → Update branch**,完成後到 Actions 手動發布一次(見下方) |
| 每週同步官方:排程快被停用了 | main 超過 42 天沒有新 commit | 見下方「排程被停用」。這種情況同步和發布照常進行 |
| 每週同步官方:其他錯誤 | 同步流程在預期外的地方出錯 | 看錯誤訊息,或請 Claude 幫忙看 |
| 檢查自訂詞庫、測試詞庫腳本 | PR 或 main 改到詞庫、腳本時 | 打開那次執行,錯誤會標在 PR 檔案的那一行或寫在摘要、紀錄裡。PR 的話先修好再合併 |

## 手動操作

**手動發布**:到 [Actions](https://github.com/andrewlin9697/win-mcbopomofo/actions) → 左邊選「建置並發布安裝檔」→ 右邊 **Run workflow** → 保持 `main` → 綠色 **Run workflow**。
如果這個官方版本已經發布過,它會直接結束;想重新編一次就勾選「強制重新發布」(會刪掉同名的舊 Release 再發一次)。

**手動同步**:同上,但選「每週同步官方」。

**Sync fork 之後補發**:按完 Sync fork → Update branch,下一次每週同步會自動補發;想馬上拿到就手動發布一次。

## 排程被停用

GitHub 的規則(見 [GitHub 文件](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)):公開 repo 60 天沒有任何活動,排程流程會被自動停用。官方很久沒更新時,本 fork 也不會有新 commit,就可能發生。

這裡的做法是**提醒、不自動製造活動**:「每週同步官方」發現 main 已經 42 天以上沒有新 commit,就讓那次執行顯示成紅色(錯誤訊息標題「每週同步排程快被停用了」,寫著預計停用的日期),GitHub 會寄失敗通知信給你。每週檢查一次,所以停用前會提醒兩到三次。

- 在那之前 main 有新 commit(例如合併一個 PR)就會重新計算。
- 已經被停用時:到 Actions → 左邊「每週同步官方」,上方會有停用提示,按 **Enable workflow** 就恢復。
- GitHub 文件沒有定義「活動」包含哪些事,提醒是用 main 最後一個 commit 的時間估算的,日期可能有些誤差。
