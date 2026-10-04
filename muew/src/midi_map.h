// 0.118.0 MIDI learn: a global, per-user map from MIDI controller number (CC) to AU parameter ID.
// It lives outside presets and outside the AU parameter list (no schema change); the standalone
// stores its text form in user defaults. One CC drives one parameter and one parameter has one CC:
// learning either side again replaces the old pairing.
#pragma once
#include <cctype>
#include <cstdlib>
#include <string>
namespace muew {
class MidiMap {
public:
    static constexpr int kCCs = 128;
    MidiMap() { clear(); }
    void clear() { for (int& p : param_) p = -1; }
    // Learnable CCs: everything the parser hands over as a plain controller (CC1, 7, 64 and the channel mode
    // messages have fixed jobs, and the parser never reports them as controllers).
    static bool learnable(int cc) { return cc >= 0 && cc < 120 && cc != 1 && cc != 7 && cc != 64; }
    bool set(int cc, int param) {
        if (!learnable(cc) || param < 0) return false;
        forgetParam(param);
        param_[cc] = param;
        return true;
    }
    void forgetParam(int param) { for (int& p : param_) if (p == param) p = -1; }
    void forgetCC(int cc) { if (cc >= 0 && cc < kCCs) param_[cc] = -1; }
    int paramFor(int cc) const { return cc >= 0 && cc < kCCs ? param_[cc] : -1; }
    int ccFor(int param) const { for (int c = 0; c < kCCs; ++c) if (param_[c] == param && param >= 0) return c; return -1; }
    int count() const { int n = 0; for (int p : param_) n += p >= 0; return n; }
    // "74:4,21:5" in CC order. Decode ignores anything malformed rather than failing the whole map.
    std::string encode() const {
        std::string s;
        for (int c = 0; c < kCCs; ++c) if (param_[c] >= 0) { if (!s.empty()) s += ','; s += std::to_string(c) + ":" + std::to_string(param_[c]); }
        return s;
    }
    void decode(const std::string& text) {
        clear();
        size_t i = 0;
        while (i < text.size()) {
            size_t e = text.find(',', i); if (e == std::string::npos) e = text.size();
            const std::string item = text.substr(i, e - i); i = e + 1;
            const size_t colon = item.find(':'); if (colon == std::string::npos || colon == 0 || colon + 1 >= item.size()) continue;
            bool digits = true; for (size_t k = 0; k < item.size(); ++k) if (k != colon && !std::isdigit((unsigned char)item[k])) digits = false;
            if (!digits || item.size() > 12) continue;
            set(std::atoi(item.substr(0, colon).c_str()), std::atoi(item.substr(colon + 1).c_str()));
        }
    }
private:
    int param_[kCCs];
};
} // namespace muew
