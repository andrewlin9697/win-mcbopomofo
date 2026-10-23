#!/usr/bin/env python3
"""檢查 my-phrases/*.txt 的自訂詞(只在 CI 跑,也可以在本機跑)。

用法:python3 my-scripts/check_phrases.py [--data data/data.txt] [my-phrases/*.txt ...]

錯誤(有任何一個就以 1 結束):
  - 格式不是「詞 注音」,或檔案有 BOM / CRLF
  - 詞夾英文字母、數字或符號(注音只能對應中文字),或只有一個字
  - 音節超過 8 個(引擎 ReadingGrid::kMaximumSpanLength,超過就沒辦法當成一個詞打出來)
  - 音節不合法,或不是 data.txt 裡有的音節
  - 某個字的讀音不在 data.txt 的單字讀音裡
  - 詞已經在 data.txt 裡(不管讀音)
  - 同一個詞重複出現,或出現在不同分類
  - 不同的詞用同一組注音(只有一個能當第一個候選)

另外會列出含破音字(data.txt 裡有兩種以上單字讀音)的詞,讓人逐一確認讀音。
有設定 GITHUB_STEP_SUMMARY 時,結果也會寫進 workflow 的摘要。
"""

import argparse
import glob
import os
import re
import sys
from collections import defaultdict

MAX_SYLLABLES = 8
# 聲母、介音、韻母、聲調(輕聲 ˙ 依小麥注音的慣例放在最後)
SYLLABLE_RE = re.compile(r"^[ㄅ-ㄙ]?[ㄧㄨㄩ]?[ㄚ-ㄦ]?[ˊˇˋ˙]?$")
CJK_RE = re.compile(r"^[㐀-䶿一-鿿豈-﫿]+$")


def load_data(path):
    """回傳 (單字 -> {讀音: 分數}, data.txt 裡所有的詞, 所有單音節的 key)。"""
    char_readings = defaultdict(dict)
    values = set()
    syllables = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) != 3 or parts[0].startswith("_"):
                continue
            key, value, score = parts[0], parts[1], float(parts[2])
            values.add(value)
            if "-" not in key:
                syllables.add(key)
                if len(value) == 1:
                    old = char_readings[value].get(key)
                    char_readings[value][key] = score if old is None else max(old, score)
    return char_readings, values, syllables


def read_entries(path, name, errors):
    """name 是顯示用的路徑(相對於 repo 根目錄)。"""
    entries = []
    with open(path, "rb") as f:
        raw = f.read()
    path = name
    if raw.startswith(b"\xef\xbb\xbf"):
        errors.append(f"{path}: 檔案開頭有 BOM,請存成沒有 BOM 的 UTF-8")
    if b"\r" in raw:
        errors.append(f"{path}: 有 CR 換行,請用 LF")
    for lineno, line in enumerate(raw.decode("utf-8-sig").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split()
        where = f"{path}:{lineno}"
        if len(parts) != 2:
            errors.append(f"{where}: 格式要是「詞 注音」兩欄:{line!r}")
            continue
        entries.append((where, path, parts[0], parts[1]))
    return entries


def check_entry(where, value, reading, char_readings, data_values, syllables, errors):
    if not CJK_RE.match(value):
        errors.append(f"{where}: 「{value}」只能有中文字(夾英文字母的詞,注音只能對應中文部分,請只收中文部分)")
        return
    if len(value) < 2:
        errors.append(f"{where}: 「{value}」是單字詞,不收")
    syl = reading.split("-")
    if len(syl) > MAX_SYLLABLES:
        errors.append(f"{where}: 「{value}」有 {len(syl)} 個音節,超過引擎上限 {MAX_SYLLABLES}")
    if len(syl) != len(value):
        errors.append(f"{where}: 「{value}」有 {len(value)} 個字,注音卻有 {len(syl)} 個音節")
        return
    for c, s in zip(value, syl):
        if not s or not SYLLABLE_RE.match(s) or s in "ˊˇˋ˙":
            errors.append(f"{where}: 「{value}」的音節「{s}」不合法")
        elif s not in syllables:
            errors.append(f"{where}: 「{value}」的音節「{s}」不在 data.txt 裡")
        elif s not in char_readings.get(c, {}):
            known = "、".join(sorted(char_readings.get(c, {}))) or "沒有"
            errors.append(f"{where}: 「{value}」的「{c}」讀「{s}」不在 data.txt 的單字讀音裡(data.txt:{known})")
    if value in data_values:
        errors.append(f"{where}: 「{value}」data.txt 已經有了")


def polyphone_rows(entries, char_readings):
    """依「字 + 用的讀音」分組,列出用到的詞。"""
    groups = defaultdict(list)
    for _, _, value, reading in entries:
        for c, s in zip(value, reading.split("-")):
            if len(char_readings.get(c, {})) > 1 and value not in groups[(c, s)]:
                groups[(c, s)].append(value)
    rows = []
    for (c, s), words in sorted(groups.items()):
        readings = char_readings[c]
        top = max(readings, key=readings.get)
        others = "、".join(r for r in sorted(readings, key=readings.get, reverse=True) if r != s)
        mark = "" if s == top else "(不是最常見的讀音)"
        rows.append(f"| {c} | {s}{mark} | {others} | {'、'.join(words)} |")
    return rows


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--data", default=os.path.join(root, "data", "data.txt"))
    parser.add_argument("files", nargs="*")
    args = parser.parse_args()
    files = args.files or sorted(glob.glob(os.path.join(root, "my-phrases", "*.txt")))
    if not files:
        print("找不到 my-phrases/*.txt", file=sys.stderr)
        return 1

    char_readings, data_values, syllables = load_data(args.data)
    errors = []
    entries = []
    names = {path: os.path.relpath(path, root) for path in files}
    for path in files:
        entries += read_entries(path, names[path], errors)

    seen_pair = {}
    value_file = {}
    reading_value = {}
    for where, path, value, reading in entries:
        check_entry(where, value, reading, char_readings, data_values, syllables, errors)
        if (value, reading) in seen_pair:
            errors.append(f"{where}: 「{value} {reading}」和 {seen_pair[(value, reading)]} 重複")
        seen_pair.setdefault((value, reading), where)
        if value_file.setdefault(value, path) != path:
            errors.append(f"{where}: 「{value}」也出現在 {value_file[value]},各分類之間不要重複")
        other = reading_value.setdefault(reading, (value, where))
        if other[0] != value:
            errors.append(f"{where}: 「{value}」和 {other[1]} 的「{other[0]}」同音({reading}),只有一個能當第一個候選")

    per_file = defaultdict(lambda: [0, set()])
    for _, path, value, _ in entries:
        per_file[path][0] += 1
        per_file[path][1].add(value)

    report = ["## 自訂詞庫檢查", "", "| 檔案 | 詞數 | 行數(含多種讀音) |", "| --- | --- | --- |"]
    for path in files:
        n, words = per_file[names[path]]
        report.append(f"| {names[path]} | {len(words)} | {n} |")
    total_words = len({v for _, _, v, _ in entries})
    report.append(f"| 合計 | {total_words} | {len(entries)} |")
    report += ["", f"### 錯誤:{len(errors)} 個", ""]
    report += [f"- {e}" for e in errors]
    rows = polyphone_rows(entries, char_readings)
    report += ["", f"### 含破音字的詞({len(rows)} 組,請確認讀音)", "",
               "| 字 | 這裡用的讀音 | data.txt 的其他讀音 | 詞 |", "| --- | --- | --- | --- |"]
    report += rows
    text = "\n".join(report) + "\n"
    print(text)
    if os.environ.get("GITHUB_ACTIONS"):
        # 在 PR 的檔案上標出有問題的那一行
        for e in errors:
            m = re.match(r"^(.+?):(\d+): (.*)$", e)
            if m:
                print(f"::error file={m.group(1)},line={m.group(2)}::{m.group(3)}")
            else:
                print(f"::error::{e}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
