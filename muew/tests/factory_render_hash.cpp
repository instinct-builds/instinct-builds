// Compare a release against its predecessor on the same compiler/architecture.
// Float bytes differ between Linux and macOS; never hard-code a cross-platform hash.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/synth.h"
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
using namespace muew;
int main() {
    uint64_t hash = 1469598103934665603ULL;
    for (const Preset& p : factoryPresets()) {
        Synth s; s.init(44100); s.setParams(p.voice, p.routes); s.setFX(p.fx); s.noteOn(60, .8f);
        std::vector<float> left(22050), right(22050);
        s.renderPlanar(left.data(), right.data(), (int)left.size());
        for (float sample : left) {
            uint32_t bits; std::memcpy(&bits, &sample, sizeof bits);
            for (int k=0;k<4;++k) { hash ^= (bits>>(8*k))&255u; hash *= 1099511628211ULL; }
        }
    }
    std::printf("%zu %016llx\n", factoryPresets().size(), (unsigned long long)hash);
}
