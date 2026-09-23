// preset_bank.h - a named collection of .muew preset files loaded from a
// directory (the factory bank ships in presets/). Zero dependencies beyond
// the C++17 standard library.
#pragma once
#include "preset.h"
#include <algorithm>
#include <cctype>
#include <set>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace muew {

struct NamedPreset {
    std::string name; // filename stem
    std::string path;
    Preset preset;
};

class PresetBank {
public:
    bool loadDir(const std::string& dir, std::string& err) {
        namespace fs = std::filesystem;
        presets_.clear();
        std::error_code ec;
        if (!fs::is_directory(dir, ec)) {
            err = "preset directory not found: " + dir;
            return false;
        }
        for (const auto& entry : fs::directory_iterator(dir, ec)) {
            if (!entry.is_regular_file()) continue;
            if (entry.path().extension() != ".muew") continue;
            std::ifstream f(entry.path());
            if (!f) { err = "cannot read preset: " + entry.path().string(); return false; }
            std::ostringstream ss;
            ss << f.rdbuf();
            NamedPreset np;
            np.name = entry.path().stem().string();
            np.path = entry.path().string();
            if (!np.preset.parse(ss.str())) {
                err = "failed to parse preset: " + np.path;
                return false;
            }
            presets_.push_back(std::move(np));
        }
        std::sort(presets_.begin(), presets_.end(),
                  [](const NamedPreset& a, const NamedPreset& b) { return a.name < b.name; });
        return true;
    }

    // Load in the order listed by <dir>/bank.txt (the factory/AU order).
    // Fails if the manifest names a missing file or skips a .muew file.
    bool loadManifest(const std::string& dir, std::string& err) {
        namespace fs = std::filesystem;
        PresetBank all;
        if (!all.loadDir(dir, err)) return false;
        std::ifstream m(dir + "/bank.txt");
        if (!m) { err = "missing manifest: " + dir + "/bank.txt"; return false; }
        presets_.clear();
        std::set<std::string> listed;
        std::string line;
        while (std::getline(m, line)) {
            if (line.empty() || line[0] == '#') continue;
            const NamedPreset* np = all.get(line);
            if (!np) { err = "manifest names missing preset: " + line; return false; }
            if (!listed.insert(line).second) { err = "manifest repeats preset: " + line; return false; }
            presets_.push_back(*np);
        }
        if (presets_.size() != all.size()) { err = "manifest does not list every preset file"; return false; }
        return true;
    }

    size_t size() const { return presets_.size(); }
    const std::vector<NamedPreset>& presets() const { return presets_; }

    const NamedPreset* get(const std::string& name) const {
        for (const auto& p : presets_)
            if (p.name == name) return &p;
        return nullptr;
    }

    std::vector<std::string> names() const {
        std::vector<std::string> out;
        for (const auto& p : presets_) out.push_back(p.name);
        return out;
    }

private:
    std::vector<NamedPreset> presets_;
};

// Browser filtering shared by the standalone UI and tests. Empty category
// means all; the query matches name, category, or any tag, case-insensitive.
struct PresetFilter {
    std::string category;
    std::string query;
    bool favoritesOnly = false;
};

inline std::string muewLower(std::string s) {
    for (auto& c : s) c = (char)std::tolower((unsigned char)c);
    return s;
}

inline bool presetMatches(const Preset& p, const std::string& slug, const PresetFilter& f,
                          const std::set<std::string>& favorites) {
    if (!f.category.empty() && p.info.category != f.category) return false;
    if (f.favoritesOnly && !favorites.count(slug)) return false;
    if (f.query.empty()) return true;
    const std::string q = muewLower(f.query);
    if (muewLower(p.info.name).find(q) != std::string::npos) return true;
    if (muewLower(p.info.category).find(q) != std::string::npos) return true;
    for (const auto& t : p.info.tags)
        if (muewLower(t).find(q) != std::string::npos) return true;
    return false;
}

} // namespace muew
