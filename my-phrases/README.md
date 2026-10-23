# 自訂詞庫

這個資料夾是本 fork 自己加的(不是官方檔案):小麥注音內建詞庫(`data/data.txt`)沒有、而且引擎本來打不出來的詞。

| 檔案 | 內容 |
| --- | --- |
| `1-ee-math-physics.txt` | 電機與數理術語(電路學、電子學、電磁學、訊號與系統、數位設計、半導體、微積分、普通物理) |
| `2-courses.txt` | 這學期的課名與老師 |
| `3-nsysu.txt` | 中山大學校園名詞(都在 nsysu.edu.tw 官方網頁查證過) |
| `4-stocks-tech.txt` | 台股與科技名詞 |
| `5-daily-life.txt` | 生活常用詞(交通、機車考照、3C、耳機音響、網路與電腦、健身、FPS 遊戲) |
| `6-internet-slang.txt` | 台灣網路流行語和幹話 |

只有 `*.txt` 是詞庫檔,這份 README 不是。

## 格式

和使用者詞庫 `user.txt` 一樣,一行一筆「詞 注音」,多音節用 `-` 連接,`#` 開頭是註解:

```
克希荷夫 ㄎㄜˋ-ㄒㄧ-ㄏㄜˊ-ㄈㄨ
```

欄位順序是從引擎確認的:`UserPhrasesLM::load` 用 `ColumnOrder::VALUE_THEN_KEY` 解析,`LanguageModelLoader::addPhraseToEndOfFile` 寫入時是 `value << " " << reading`。

Windows 版的 `user.txt` 實際位置是 `%APPDATA%\WinMcBopomofo\user.txt`:`LanguageModelLoader.cpp` 只有在非 Windows(`#ifndef _WIN32`)才會在後面多加一層 `mcbopomofo`,`main.cpp` 開啟使用者詞庫時也是用 `userDirectory() + "/user.txt"`。

## 規則(`my-scripts/check_phrases.py` 會檢查)

- 不收單字詞;最多 8 個音節(引擎 `ReadingGrid::kMaximumSpanLength`,超過就不能當成一個詞打出來)。
- 只能有中文字。夾英文字母的詞(EMI 中心、ABF 載板),注音只能對應中文部分,打中文部分就會冒出英文字母,反而干擾一般的「中心」「載板」,所以只收中文部分。
- 每個音節要合法,每個字的讀音要在 `data.txt` 的單字讀音裡。
- 詞不能已經在 `data.txt` 裡;分類之間不能重複;不同的詞不能用同一組注音(只有一個能當第一個候選)。
- 含破音字的詞會列在檢查結果裡,加詞時要逐一確認讀音。
- 讀音照 `data.txt` 的慣例:「波」ㄅㄛ/ㄆㄛ、「比較」的「較」ㄐㄧㄠˋ/ㄐㄧㄠˇ、「一」「不」的變調,`data.txt` 兩種都收的,這裡也兩種都收。人名遇到破音字(王朝欽的「朝」)兩種讀音都收。

另外 CI 會用小麥注音的引擎(只編 `src/Server/Engine`)實際組字(`my-scripts/engine-check`):

- 載入 `data.txt` 和這裡的詞,輸入每個詞的注音,組字結果和第一個候選都要是這個詞。
- 不載入這裡的詞,引擎本來就打得出來的,是多餘的,不收。

## 加詞

1. 在對應的檔案加一行「詞 注音」。
2. 開 PR,「檢查自訂詞庫」流程會自動跑;失敗時錯誤會標在 PR 的檔案那一行,摘要頁有完整結果和破音字清單。

想在自己電腦先檢查(Linux 或 macOS,需要 Python 3、CMake、C++17 編譯器):

```sh
python3 my-scripts/check_phrases.py
cmake -S my-scripts/engine-check -B /tmp/engine-check -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/engine-check
/tmp/engine-check/engine_check data/data.txt my-phrases/*.txt
```
