# 我的 fork 說明(自動編譯、發布、每週同步官方)

這個 repo fork 自官方的 [openvanilla/win-mcbopomofo](https://github.com/openvanilla/win-mcbopomofo)(小麥注音 Windows 版)。
官方不發行安裝檔,所以這裡用 GitHub Actions 自己編譯,把安裝檔放在 [Releases](https://github.com/andrewlin9697/win-mcbopomofo/releases)。

- 官方原有的檔案一律不改,本 fork 只會新增自己的檔案:`.github/workflows/my-*.yml`、`my-phrases/`、`my-scripts/`、`MY-SETUP.md`。
- 這裡編出來的是**非官方**、**沒有數位簽章**的安裝檔。
- 不要對官方 repo 開 PR 或 issue(官方也寫明不收)。在 repo 頁面看到 **Contribute → Open pull request** 時不要按。

## 下載與安裝

1. 打開 [最新版 Release](https://github.com/andrewlin9697/win-mcbopomofo/releases/latest),下載 `Win-McBopomofo-Installer.msi`。x64、x86、ARM64 都包在同一個安裝檔裡。
2. (建議)核對檔案沒被動過:在下載資料夾按右鍵 → 在終端機中開啟,執行
   ```powershell
   (Get-FileHash .\Win-McBopomofo-Installer.msi -Algorithm SHA256).Hash
   ```
   印出來的值要和 Release 頁上寫的 SHA256 一樣(大小寫不用管)。
3. 執行 `.msi`。因為沒有簽章,Windows 可能跳出「Windows 已保護您的電腦」,按「其他資訊」→「仍要執行」。

版本名稱看得出對應官方哪個 commit,例如 `upstream-2026.10.09-978b39d` 就是官方 2026-10-09(台灣時間)的 commit `978b39d`。

## 自動流程

| 流程(Actions 頁左邊的名字) | 檔案 | 什麼時候跑 | 做什麼 |
| --- | --- | --- | --- |
| 每週同步官方 | `my-sync.yml` | 每週六台灣時間 09:17;也可以手動執行 | 抓官方 main。沒有新 commit 而且最新版已經發布過 → 什麼都不做。有新 commit → 合併進 main 並推送,接著建置並發布。官方最新版還沒發布 → 補發。 |
| 建置並發布安裝檔 | `my-release.yml` | 手動執行;被「每週同步官方」呼叫;PR 改到 `.github/workflows/my-*.yml` 時 | 在 Windows 上執行 `build_msi.ps1`(Release),發布 Release 並附上 `.msi` 和 `.sha256`。這個官方版本已經發布過就不做事(除非勾選「強制重新發布」)。PR 時只 build、不發布。 |
| Build and Test(官方原有) | `build.yml` | push 到 main、對 main 開 PR 時 | 官方的編譯測試。自動同步推送的 commit 不會觸發它。 |

兩個自己的流程不會同時跑,後來的會排隊等前一個結束。

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
