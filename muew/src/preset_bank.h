// preset_bank.h - a named collection of .muew preset files loaded from a
// directory (the factory bank ships in presets/). Zero dependencies beyond
// the C++17 standard library.
#pragma once
#include "preset.h"
#include <algorithm>
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

} // namespace muew
