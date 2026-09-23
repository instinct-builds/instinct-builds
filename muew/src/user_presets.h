// user_presets.h - the user's saved presets: plain .muew files in one folder
// (~/Music/MUEW/Presets on macOS), shared by the standalone app and the AU.
// Portable C++17 so it is unit-tested on every platform.
#pragma once
#include "ui_model.h"
#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <system_error>

namespace muew {
namespace user {

namespace fs = std::filesystem;

// File-system-safe stem from a display name.
inline std::string fileStem(const std::string& name) {
    std::string s;
    for (char c : name) {
        unsigned char u = (unsigned char)c;
        if (std::isalnum(u) || c == ' ' || c == '-' || c == '_' || u >= 0x80) s += c;
    }
    size_t a = s.find_first_not_of(' '), b = s.find_last_not_of(' ');
    s = a == std::string::npos ? std::string() : s.substr(a, b - a + 1);
    if (s.size() > 60) s.resize(60);
    return s.empty() ? std::string("User Preset") : s;
}

inline bool readText(const fs::path& p, std::string& out) {
    std::ifstream in(p, std::ios::binary);
    if (!in) return false;
    std::ostringstream ss; ss << in.rdbuf();
    out = ss.str();
    return true;
}

// Writes via a temp file + rename so a crash never leaves half a preset.
inline bool writeText(const fs::path& p, const std::string& text) {
    fs::path tmp = p; tmp += ".tmp";
    {
        std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
        if (!out) return false;
        out << text;
        if (!out.good()) return false;
    }
    std::error_code ec;
    fs::rename(tmp, p, ec);
    if (ec) { fs::remove(tmp, ec); return false; }
    return true;
}

// Replaces lib.user with every readable .muew file in dir, sorted by name.
inline int load(const std::string& dir, ui::Library& lib) {
    lib.user.clear(); lib.userFiles.clear();
    std::error_code ec;
    if (dir.empty() || !fs::is_directory(dir, ec)) return 0;
    std::vector<std::pair<Preset, std::string>> found;
    for (fs::directory_iterator it(dir, ec), end; !ec && it != end; it.increment(ec)) {
        const fs::path& p = it->path();
        if (p.extension() != ".muew" || !it->is_regular_file(ec)) continue;
        std::string text; Preset pr;
        if (!readText(p, text) || !pr.parse(text)) continue;
        if (pr.info.name.empty()) pr.info.name = p.stem().string();
        found.push_back({pr, p.filename().string()});
        if (found.size() >= 1000) break;
    }
    std::sort(found.begin(), found.end(), [](const auto& a, const auto& b) {
        std::string x = muewLower(a.first.info.name), y = muewLower(b.first.info.name);
        return x != y ? x < y : a.second < b.second;
    });
    for (auto& f : found) { lib.user.push_back(f.first); lib.userFiles.push_back(f.second); }
    return (int)lib.user.size();
}

// A display name not already used by a factory or user preset.
inline std::string uniqueName(const std::string& wanted, const ui::Library& lib) {
    std::string base = wanted.empty() ? std::string("User Preset") : wanted;
    if (lib.indexOfName(base) < 0) return base;
    for (int n = 2; n < 1000; ++n) {
        std::string c = base + " " + std::to_string(n);
        if (lib.indexOfName(c) < 0) return c;
    }
    return base + " copy";
}

// Saves `sound` under `name` (made unique), reloads the library and returns
// the new preset's library index, or -1 on failure.
inline int save(const std::string& dir, Preset sound, const std::string& name, ui::Library& lib) {
    std::error_code ec;
    fs::create_directories(dir, ec);
    if (!fs::is_directory(dir, ec)) return -1;
    sound.info.name = uniqueName(name, lib);
    sound.info.author = "User";
    if (sound.info.category.empty()) sound.info.category = "Pad";
    if (std::find(sound.info.tags.begin(), sound.info.tags.end(), "user") == sound.info.tags.end())
        sound.info.tags.push_back("user");
    std::string stem = fileStem(sound.info.name), file = stem + ".muew";
    for (int n = 2; fs::exists(fs::path(dir) / file, ec) && n < 1000; ++n) file = stem + " " + std::to_string(n) + ".muew";
    if (!writeText(fs::path(dir) / file, sound.serialize())) return -1;
    load(dir, lib);
    return lib.indexOfUserFile(file);
}

// 0.11.0 Import: copies a .muew file from anywhere into the user folder so it
// shows under the Imported bank. The sound is kept as authored; a missing
// author (or one claiming to be "User") becomes "Imported" so it never mixes
// with presets saved in MUEW. Returns the library index or -1.
inline int importFile(const std::string& dir, const std::string& src, ui::Library& lib) {
    std::string text; Preset pr;
    if (src.empty() || !readText(fs::path(src), text) || !pr.parse(text)) return -1;
    std::error_code ec;
    fs::create_directories(dir, ec);
    if (!fs::is_directory(dir, ec)) return -1;
    if (pr.info.name.empty()) pr.info.name = fs::path(src).stem().string();
    pr.info.name = uniqueName(pr.info.name, lib);
    if (pr.info.author.empty() || pr.info.author == "User") pr.info.author = "Imported";
    if (pr.info.category.empty()) pr.info.category = "Pad";
    std::string stem = fileStem(pr.info.name), file = stem + ".muew";
    for (int n = 2; fs::exists(fs::path(dir) / file, ec) && n < 1000; ++n) file = stem + " " + std::to_string(n) + ".muew";
    if (!writeText(fs::path(dir) / file, pr.serialize())) return -1;
    load(dir, lib);
    return lib.indexOfUserFile(file);
}

// Writes a shareable .muew file anywhere (the Export button).
inline bool exportTo(const std::string& path, const Preset& sound) {
    return !path.empty() && writeText(fs::path(path), sound.serialize());
}

} // namespace user
} // namespace muew
