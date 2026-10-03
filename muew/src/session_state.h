// 0.100.0 standalone session: what the editor shows at quit, as one string.
// Line 1 is "muew-session 1 <slug>" (slug empty when the sound is not a library
// sound), the rest is the sound in the normal preset text. Decoding never
// trusts the string: a wrong header or an unparsable sound yields false.
#pragma once
#include "preset.h"
#include <string>
namespace muew {
namespace session {
inline std::string encode(const std::string& slug, const Preset& p) {
    return "muew-session 1 " + slug + "\n" + p.serialize();
}
inline bool decode(const std::string& text, std::string& slug, Preset& out) {
    const std::string tag = "muew-session 1 ";
    if (text.compare(0, tag.size(), tag) != 0) return false;
    size_t nl = text.find('\n');
    if (nl == std::string::npos) return false;
    slug = text.substr(tag.size(), nl - tag.size());
    Preset p;
    if (!p.parse(text.substr(nl + 1))) return false;
    out = p;
    return true;
}
} // namespace session
} // namespace muew
