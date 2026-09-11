// license.h - MUEW offline licensing: HMAC-signed license keys and 3-device
// activation records. Zero dependencies, C++17, original code.
//
// The roadmap calls for "our own simple license-key scheme, not iLok-style
// DRM", so this is honest-user licensing: the key's activation limit lives
// inside an HMAC-SHA256-signed payload, so the 3-device limit cannot be
// raised by editing local files. Each activation record is an HMAC token
// bound to the key id and the device hash, and the store file carries its
// own HMAC checksum so hand-edited entries are detected on load.
//
// Key text form:  MUEW3-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX
// Record bytes:   14-byte payload || 16-byte truncated HMAC-SHA256
// Payload:        "MU" | version(1) | maxDevices(1) | features(u16le) |
//                 issueDays(u32le) | nonce(4)
#pragma once

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <ctime>
#include <fstream>
#include <random>
#include <sstream>
#include <string>
#include <vector>
#include <unistd.h>

namespace muew {
namespace license {

// ---------------- SHA-256 (FIPS 180-4) ----------------
class Sha256 {
public:
    Sha256() { reset(); }

    void reset() {
        state_ = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                  0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};
        bitLen_ = 0;
        bufLen_ = 0;
    }

    void update(const uint8_t* data, size_t len) {
        for (size_t i = 0; i < len; ++i) {
            buf_[bufLen_++] = data[i];
            if (bufLen_ == 64) {
                compress(buf_.data());
                bufLen_ = 0;
                bitLen_ += 512;
            }
        }
    }
    void update(const std::string& s) {
        update(reinterpret_cast<const uint8_t*>(s.data()), s.size());
    }

    std::array<uint8_t, 32> finish() {
        uint64_t totalBits = bitLen_ + bufLen_ * 8;
        buf_[bufLen_++] = 0x80;
        if (bufLen_ > 56) {
            while (bufLen_ < 64) buf_[bufLen_++] = 0;
            compress(buf_.data());
            bufLen_ = 0;
        }
        while (bufLen_ < 56) buf_[bufLen_++] = 0;
        for (int i = 7; i >= 0; --i) buf_[bufLen_++] = (uint8_t)(totalBits >> (i * 8));
        compress(buf_.data());
        std::array<uint8_t, 32> out;
        for (int i = 0; i < 8; ++i) {
            out[i * 4 + 0] = (uint8_t)(state_[i] >> 24);
            out[i * 4 + 1] = (uint8_t)(state_[i] >> 16);
            out[i * 4 + 2] = (uint8_t)(state_[i] >> 8);
            out[i * 4 + 3] = (uint8_t)(state_[i]);
        }
        return out;
    }

    static std::array<uint8_t, 32> hash(const std::string& s) {
        Sha256 h;
        h.update(s);
        return h.finish();
    }

private:
    static uint32_t rotr(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }

    void compress(const uint8_t* block) {
        static const uint32_t K[64] = {
            0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
            0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
            0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
            0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
            0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
            0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
            0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
            0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};
        uint32_t w[64];
        for (int i = 0; i < 16; ++i)
            w[i] = (uint32_t)block[i * 4] << 24 | (uint32_t)block[i * 4 + 1] << 16 |
                   (uint32_t)block[i * 4 + 2] << 8 | (uint32_t)block[i * 4 + 3];
        for (int i = 16; i < 64; ++i) {
            uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
            uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }
        uint32_t a = state_[0], b = state_[1], c = state_[2], d = state_[3];
        uint32_t e = state_[4], f = state_[5], g = state_[6], h = state_[7];
        for (int i = 0; i < 64; ++i) {
            uint32_t S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
            uint32_t ch = (e & f) ^ (~e & g);
            uint32_t t1 = h + S1 + ch + K[i] + w[i];
            uint32_t S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
            uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
            uint32_t t2 = S0 + maj;
            h = g; g = f; f = e; e = d + t1;
            d = c; c = b; b = a; a = t1 + t2;
        }
        state_[0] += a; state_[1] += b; state_[2] += c; state_[3] += d;
        state_[4] += e; state_[5] += f; state_[6] += g; state_[7] += h;
    }

    std::array<uint32_t, 8> state_{};
    std::array<uint8_t, 64> buf_{};
    uint64_t bitLen_ = 0;
    size_t bufLen_ = 0;
};

inline std::string toHex(const uint8_t* data, size_t n) {
    static const char* digits = "0123456789abcdef";
    std::string s;
    s.reserve(n * 2);
    for (size_t i = 0; i < n; ++i) {
        s.push_back(digits[data[i] >> 4]);
        s.push_back(digits[data[i] & 15]);
    }
    return s;
}

// HMAC-SHA256 (RFC 2104), 64-byte block size.
inline std::array<uint8_t, 32> hmacSha256(const std::string& key, const std::string& msg) {
    std::array<uint8_t, 64> k{};
    if (key.size() > 64) {
        auto h = Sha256::hash(key);
        std::copy(h.begin(), h.end(), k.begin());
    } else {
        std::copy(key.begin(), key.end(), k.begin());
    }
    std::string ipad(64, '\x36'), opad(64, '\x5c');
    for (int i = 0; i < 64; ++i) {
        ipad[i] = (char)(ipad[i] ^ k[i]);
        opad[i] = (char)(opad[i] ^ k[i]);
    }
    Sha256 inner;
    inner.update(ipad);
    inner.update(msg);
    auto ih = inner.finish();
    Sha256 outer;
    outer.update(opad);
    outer.update(std::string(reinterpret_cast<char*>(ih.data()), ih.size()));
    return outer.finish();
}

inline std::string hmacHex(const std::string& key, const std::string& msg) {
    auto h = hmacSha256(key, msg);
    return toHex(h.data(), h.size());
}

inline bool ctEqual(const uint8_t* a, const uint8_t* b, size_t n) {
    uint8_t diff = 0;
    for (size_t i = 0; i < n; ++i) diff |= (uint8_t)(a[i] ^ b[i]);
    return diff == 0;
}

// ---------------- base32 (Crockford-style alphabet: no I, L, O, U) ----------------
inline const char* kBase32Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

inline std::string base32Encode(const uint8_t* data, size_t n) {
    std::string out;
    uint32_t acc = 0;
    int bits = 0;
    for (size_t i = 0; i < n; ++i) {
        acc = (acc << 8) | data[i];
        bits += 8;
        while (bits >= 5) {
            bits -= 5;
            out.push_back(kBase32Alphabet[(acc >> bits) & 31]);
        }
    }
    if (bits > 0) out.push_back(kBase32Alphabet[(acc << (5 - bits)) & 31]);
    return out;
}

inline bool base32Decode(const std::string& in, std::vector<uint8_t>& out) {
    out.clear();
    uint32_t acc = 0;
    int bits = 0;
    for (char ch : in) {
        char c = ch;
        if (c >= 'a' && c <= 'z') c = (char)(c - 'a' + 'A');
        if (c == 'O') c = '0';          // typing aliases
        if (c == 'I' || c == 'L') c = '1';
        const char* p = nullptr;
        for (const char* a = kBase32Alphabet; *a; ++a)
            if (*a == c) { p = a; break; }
        if (!p) return false;
        acc = (acc << 5) | (uint32_t)(p - kBase32Alphabet);
        bits += 5;
        if (bits >= 8) {
            bits -= 8;
            out.push_back((uint8_t)(acc >> bits));
        }
    }
    return bits < 5;
}

// ---------------- license key ----------------
struct Key {
    uint8_t version = 1;
    uint8_t maxDevices = 3;
    uint16_t features = 1;   // bit 0: full instrument
    uint32_t issueDays = 0;  // days since unix epoch
    std::array<uint8_t, 4> nonce{};
    std::string encoded;     // canonical MUEW3-XXXX-... text
};

namespace detail {
constexpr size_t kPayloadBytes = 14;
constexpr size_t kSigBytes = 16;
constexpr size_t kRecordBytes = kPayloadBytes + kSigBytes; // 30 -> 48 base32 chars

inline std::array<uint8_t, kPayloadBytes> packPayload(const Key& k) {
    std::array<uint8_t, kPayloadBytes> p{};
    p[0] = 'M'; p[1] = 'U';
    p[2] = k.version;
    p[3] = k.maxDevices;
    p[4] = (uint8_t)(k.features & 0xFF);
    p[5] = (uint8_t)(k.features >> 8);
    p[6] = (uint8_t)(k.issueDays & 0xFF);
    p[7] = (uint8_t)((k.issueDays >> 8) & 0xFF);
    p[8] = (uint8_t)((k.issueDays >> 16) & 0xFF);
    p[9] = (uint8_t)((k.issueDays >> 24) & 0xFF);
    for (int i = 0; i < 4; ++i) p[10 + i] = k.nonce[i];
    return p;
}

inline bool unpackPayload(const uint8_t* p, Key& k) {
    if (p[0] != 'M' || p[1] != 'U') return false;
    k.version = p[2];
    k.maxDevices = p[3];
    k.features = (uint16_t)(p[4] | (p[5] << 8));
    k.issueDays = (uint32_t)p[6] | ((uint32_t)p[7] << 8) | ((uint32_t)p[8] << 16) | ((uint32_t)p[9] << 24);
    for (int i = 0; i < 4; ++i) k.nonce[i] = p[10 + i];
    return true;
}

inline std::string payloadString(const std::array<uint8_t, kPayloadBytes>& p) {
    return std::string(reinterpret_cast<const char*>(p.data()), p.size());
}

// Short stable id for one key payload, used to bind activation records.
inline std::string keyIdFromPayload(const std::array<uint8_t, kPayloadBytes>& p) {
    auto h = Sha256::hash(payloadString(p));
    return toHex(h.data(), 8);
}

inline std::array<uint8_t, kSigBytes> signPayload(const std::string& secret,
                                                  const std::array<uint8_t, kPayloadBytes>& p) {
    auto h = hmacSha256(secret, payloadString(p));
    std::array<uint8_t, kSigBytes> sig{};
    std::copy_n(h.begin(), kSigBytes, sig.begin());
    return sig;
}

inline std::string groupKeyText(const std::string& b32) {
    std::string out = "MUEW3";
    for (size_t i = 0; i < b32.size(); ++i) {
        if (i % 4 == 0) out.push_back('-');
        out.push_back(b32[i]);
    }
    return out;
}
} // namespace detail

inline std::string generateKey(const std::string& secret, uint8_t maxDevices = 3,
                               uint16_t features = 1, uint32_t issueDays = 0) {
    if (issueDays == 0) issueDays = (uint32_t)(std::time(nullptr) / 86400);
    Key k;
    k.maxDevices = maxDevices;
    k.features = features;
    k.issueDays = issueDays;
    std::random_device rd;
    for (auto& b : k.nonce) b = (uint8_t)rd();

    auto payload = detail::packPayload(k);
    auto sig = detail::signPayload(secret, payload);
    std::array<uint8_t, detail::kRecordBytes> rec{};
    std::copy(payload.begin(), payload.end(), rec.begin());
    std::copy(sig.begin(), sig.end(), rec.begin() + detail::kPayloadBytes);
    return detail::groupKeyText(base32Encode(rec.data(), rec.size()));
}

inline bool validateKey(const std::string& encoded, const std::string& secret,
                        Key& out, std::string& err) {
    // Normalize: require the MUEW3 prefix, keep only base32 body characters.
    std::string upper;
    for (char c : encoded) upper.push_back((c >= 'a' && c <= 'z') ? (char)(c - 'a' + 'A') : c);
    if (upper.compare(0, 5, "MUEW3") != 0) {
        err = "not a MUEW3 license key";
        return false;
    }
    std::string body;
    for (size_t i = 5; i < upper.size(); ++i) {
        char c = upper[i];
        if (c == '-' || c == ' ' || c == '\t' || c == '\n' || c == '\r') continue;
        body.push_back(c);
    }
    std::vector<uint8_t> rec;
    if (!base32Decode(body, rec) || rec.size() != detail::kRecordBytes) {
        err = "malformed license key";
        return false;
    }
    Key k;
    if (!detail::unpackPayload(rec.data(), k)) {
        err = "malformed license key payload";
        return false;
    }
    auto payload = detail::packPayload(k);
    auto expect = detail::signPayload(secret, payload);
    if (!ctEqual(expect.data(), rec.data() + detail::kPayloadBytes, detail::kSigBytes)) {
        err = "license key signature mismatch";
        return false;
    }
    k.encoded = detail::groupKeyText(base32Encode(rec.data(), rec.size()));
    out = k;
    return true;
}

// Stable id for a key without re-deriving it from raw text everywhere.
inline std::string keyId(const Key& k) {
    return detail::keyIdFromPayload(detail::packPayload(k));
}

// ---------------- device identity ----------------
inline std::string sha256Hex(const std::string& s) {
    auto h = Sha256::hash(s);
    return toHex(h.data(), h.size());
}

// Best-effort stable device id: machine-id files first, hostname+user as
// fallback. Raw value stays local; only its hash is stored.
inline std::string defaultDeviceId() {
    const char* paths[] = {"/etc/machine-id", "/var/lib/dbus/machine-id"};
    for (const char* p : paths) {
        std::ifstream f(p);
        std::string line;
        if (f && std::getline(f, line) && !line.empty()) return "machine-id:" + line;
    }
    char host[256] = {0};
    gethostname(host, sizeof(host) - 1);
    const char* user = getenv("USER");
    return std::string("host:") + host + ":" + (user ? user : "unknown");
}

inline std::string defaultDeviceLabel() {
    char host[256] = {0};
    gethostname(host, sizeof(host) - 1);
    return host[0] ? std::string(host) : std::string("this device");
}

// ---------------- activation store ----------------
struct Activation {
    std::string token;      // hmac(secret, "MUEW-ACTIVATE|<keyId>|<deviceHash>")
    std::string deviceHash; // sha256 hex of the raw device id
    std::string label;
    uint32_t firstSeenDays = 0;
};

enum class ActivateResult { Ok, AlreadyActive, LimitReached, InvalidKey, StoreTampered, IoError };

inline const char* toString(ActivateResult r) {
    switch (r) {
    case ActivateResult::Ok: return "ok";
    case ActivateResult::AlreadyActive: return "device already activated";
    case ActivateResult::LimitReached: return "device limit reached";
    case ActivateResult::InvalidKey: return "store is bound to a different key";
    case ActivateResult::StoreTampered: return "license file was modified or corrupted";
    case ActivateResult::IoError: return "could not read or write the license file";
    }
    return "unknown";
}

inline std::string activationToken(const std::string& secret, const std::string& keyId,
                                   const std::string& deviceHash) {
    return hmacHex(secret, "MUEW-ACTIVATE|" + keyId + "|" + deviceHash);
}

class ActivationStore {
public:
    explicit ActivationStore(std::string path) : path_(std::move(path)) {}

    bool exists() const {
        std::ifstream f(path_);
        return f.good();
    }

    // Loads and verifies the file. Returns false on tamper or unreadable file;
    // a missing file is not an error (fresh store).
    bool load(const std::string& secret, std::string& err) {
        keyId_.clear();
        encodedKey_.clear();
        acts_.clear();
        std::ifstream f(path_);
        if (!f) return true; // fresh
        std::ostringstream body;
        std::string line, checksum;
        bool sawMagic = false;
        while (std::getline(f, line)) {
            if (line.rfind("checksum ", 0) == 0) {
                checksum = line.substr(9);
                continue;
            }
            body << line << "\n";
            if (!sawMagic) {
                if (line != "MUEW-LICENSE 1") { err = "bad license file magic"; return false; }
                sawMagic = true;
                continue;
            }
            std::istringstream ls(line);
            std::string key;
            ls >> key;
            if (key == "key") {
                ls >> encodedKey_;
            } else if (key == "key_id") {
                ls >> keyId_;
            } else if (key == "activation") {
                Activation a;
                ls >> a.token >> a.deviceHash >> a.firstSeenDays;
                std::string label;
                std::getline(ls, label);
                if (!label.empty() && label[0] == ' ') label.erase(0, 1);
                a.label = label;
                acts_.push_back(a);
            }
        }
        if (!sawMagic) { err = "bad license file magic"; return false; }
        if (checksum.empty() || !ctEqualStr(checksum, hmacHex(secret, body.str()))) {
            err = "license file checksum mismatch";
            return false;
        }
        return true;
    }

    bool save(const std::string& secret, std::string& err) const {
        std::ostringstream body;
        body << "MUEW-LICENSE 1\n";
        body << "key " << encodedKey_ << "\n";
        body << "key_id " << keyId_ << "\n";
        for (const auto& a : acts_)
            body << "activation " << a.token << " " << a.deviceHash << " "
                 << a.firstSeenDays << " " << a.label << "\n";
        std::ofstream f(path_, std::ios::trunc);
        if (!f) { err = "cannot open license file for writing"; return false; }
        f << body.str();
        f << "checksum " << hmacHex(secret, body.str()) << "\n";
        if (!f) { err = "failed writing license file"; return false; }
        return true;
    }

    const std::string& keyId() const { return keyId_; }
    const std::string& encodedKey() const { return encodedKey_; }
    const std::vector<Activation>& activations() const { return acts_; }
    int slotsUsed() const { return (int)acts_.size(); }

    ActivateResult activate(const Key& key, const std::string& secret,
                            const std::string& deviceId, const std::string& deviceLabel,
                            std::string& err) {
        std::string id = muew::license::keyId(key);
        if (!keyId_.empty() && keyId_ != id) return ActivateResult::InvalidKey;
        if (keyId_.empty()) {
            keyId_ = id;
            encodedKey_ = key.encoded;
        }
        std::string dh = sha256Hex(deviceId);
        for (const auto& a : acts_)
            if (a.deviceHash == dh && a.token == activationToken(secret, keyId_, dh))
                return ActivateResult::AlreadyActive;
        if ((int)acts_.size() >= key.maxDevices) return ActivateResult::LimitReached;
        Activation a;
        a.token = activationToken(secret, keyId_, dh);
        a.deviceHash = dh;
        a.label = deviceLabel;
        a.firstSeenDays = (uint32_t)(std::time(nullptr) / 86400);
        acts_.push_back(a);
        if (!save(secret, err)) return ActivateResult::IoError;
        return ActivateResult::Ok;
    }

    bool deactivate(const std::string& deviceId, const std::string& secret) {
        std::string dh = sha256Hex(deviceId);
        for (size_t i = 0; i < acts_.size(); ++i) {
            if (acts_[i].deviceHash == dh &&
                acts_[i].token == activationToken(secret, keyId_, dh)) {
                acts_.erase(acts_.begin() + i);
                std::string err;
                return save(secret, err);
            }
        }
        return false;
    }

    bool isActivatedFor(const std::string& deviceId, const std::string& secret) const {
        std::string dh = sha256Hex(deviceId);
        for (const auto& a : acts_)
            if (a.deviceHash == dh && a.token == activationToken(secret, keyId_, dh))
                return true;
        return false;
    }

private:
    static bool ctEqualStr(const std::string& a, const std::string& b) {
        if (a.size() != b.size()) return false;
        return ctEqual(reinterpret_cast<const uint8_t*>(a.data()),
                       reinterpret_cast<const uint8_t*>(b.data()), a.size());
    }
    std::string path_;
    std::string keyId_;
    std::string encodedKey_;
    std::vector<Activation> acts_;
};

} // namespace license
} // namespace muew
