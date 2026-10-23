// 用小麥注音的引擎檢查 my-phrases/ 的詞:
//   1. 載入 data.txt 和 my-phrases/ 的詞,逐字輸入注音,組字結果和第一個候選都要是這個詞。
//   2. 只載入 data.txt(不載入 my-phrases/),組字結果如果已經是這個詞,這個詞就是多餘的。
//
// 用法:engine_check <data.txt> <my-phrases 檔案...>
// 輸出:每個有問題的詞一行(TSV),最後一行是統計。有任何問題就以 1 結束。

#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "McBopomofoLM.h"
#include "gramambular2/reading_grid.h"

namespace {

using Formosa::Gramambular2::ReadingGrid;

struct Entry {
  std::string file;
  size_t line = 0;
  std::string value;
  std::string reading;
};

std::vector<std::string> Split(const std::string& s, char sep) {
  std::vector<std::string> out;
  std::string cur;
  std::istringstream is(s);
  while (std::getline(is, cur, sep)) {
    out.push_back(cur);
  }
  return out;
}

// 和 user.txt 一樣的格式:「詞 注音」,# 開頭是註解。
bool ReadEntries(const std::string& path, std::vector<Entry>* entries,
                 std::string* raw) {
  std::ifstream ifs(path);
  if (!ifs) {
    std::cerr << "cannot open " << path << "\n";
    return false;
  }
  std::string line;
  size_t lineNo = 0;
  while (std::getline(ifs, line)) {
    ++lineNo;
    raw->append(line);
    raw->push_back('\n');
    if (line.empty() || line[0] == '#') {
      continue;
    }
    std::istringstream is(line);
    Entry e;
    e.file = path;
    e.line = lineNo;
    if (is >> e.value >> e.reading) {
      entries->push_back(e);
    }
  }
  return true;
}

struct Typed {
  bool allInserted = true;
  std::string composed;
  std::string firstCandidate;
};

Typed TypeReading(const std::shared_ptr<McBopomofo::McBopomofoLM>& lm,
                  const std::string& reading) {
  Typed t;
  ReadingGrid grid(lm);
  for (const auto& syllable : Split(reading, '-')) {
    if (!grid.insertReading(syllable)) {
      t.allInserted = false;
    }
  }
  ReadingGrid::WalkResult result = grid.walk();
  for (const auto& v : result.valuesAsStrings()) {
    t.composed += v;
  }
  // 游標在最後面時叫出的候選清單,最長的詞排最前面。
  std::vector<ReadingGrid::Candidate> candidates =
      grid.candidatesAt(grid.readings().size());
  if (!candidates.empty()) {
    t.firstCandidate = candidates.front().value;
  }
  return t;
}

}  // namespace

int main(int argc, char* argv[]) {
  if (argc < 3) {
    std::cerr << "usage: " << argv[0] << " <data.txt> <my-phrases files...>\n";
    return 2;
  }

  std::vector<Entry> entries;
  std::string userData;
  for (int i = 2; i < argc; ++i) {
    if (!ReadEntries(argv[i], &entries, &userData)) {
      return 2;
    }
  }

  auto baseline = std::make_shared<McBopomofo::McBopomofoLM>();
  baseline->loadLanguageModel(argv[1]);
  auto withMine = std::make_shared<McBopomofo::McBopomofoLM>();
  withMine->loadLanguageModel(argv[1]);
  if (!baseline->isDataModelLoaded() || !withMine->isDataModelLoaded()) {
    std::cerr << "cannot load " << argv[1] << "\n";
    return 2;
  }
  // userData 要活到程式結束,詞典直接指向這塊記憶體。
  withMine->loadUserPhrases(userData.data(), userData.size());

  size_t redundant = 0;
  size_t notFirst = 0;
  std::cout << "status\tfile:line\tphrase\treading\tbaseline\twith_mine\t"
               "first_candidate\n";
  for (const auto& e : entries) {
    Typed mine = TypeReading(withMine, e.reading);
    Typed base = TypeReading(baseline, e.reading);
    std::string status;
    if (!mine.allInserted || mine.composed != e.value ||
        mine.firstCandidate != e.value) {
      status = "NOT_FIRST";
      ++notFirst;
    } else if (base.composed == e.value) {
      status = "REDUNDANT";
      ++redundant;
    } else {
      continue;
    }
    std::cout << status << "\t" << e.file << ":" << e.line << "\t" << e.value
              << "\t" << e.reading << "\t" << base.composed << "\t"
              << mine.composed << "\t" << mine.firstCandidate << "\n";
  }
  std::cout << "# checked=" << entries.size() << " not_first=" << notFirst
            << " redundant=" << redundant << "\n";
  return (notFirst == 0 && redundant == 0) ? 0 : 1;
}
