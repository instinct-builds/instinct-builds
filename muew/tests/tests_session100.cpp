// 0.100.0 standalone session encode/decode.
#include "../src/session_state.h"
#include "../src/factory_bank.h"
#include "../src/user_presets.h"
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <unistd.h>
using namespace muew;
static int failures = 0;
static void ck(bool ok, const char* m) { printf("%s %s\n", ok ? "ok:" : "FAIL:", m); failures += !ok; }
int main() {
    Preset p; p.parse(kFactoryPresetTexts[3].text);
    p.voice.filterCutoff = 777; p.info.name = "Edited Thing";
    std::string slug, s = session::encode("formant-talker", p);
    Preset q;
    ck(session::decode(s, slug, q), "a session decodes");
    ck(slug == "formant-talker", "slug survives");
    ck(q == p, "an edited sound comes back equal");
    s = session::encode("", p);
    ck(session::decode(s, slug, q) && slug.empty() && q == p, "empty slug (not a library sound) round-trips");
    s = session::encode("user/My Sound.muew", p);
    ck(session::decode(s, slug, q) && slug == "user/My Sound.muew", "a slug with a space and slash survives");
    ck(!session::decode("", slug, q), "empty text is rejected");
    ck(!session::decode("garbage\nmore", slug, q), "wrong header is rejected");
    ck(!session::decode("muew-session 1 x", slug, q), "no newline is rejected");
    Preset keep = p;
    ck(!session::decode("muew-session 1 x\nnot a preset at all", slug, keep) && keep == p, "unparsable sound is rejected and leaves the output alone");
    { // 0.112.0: the minimal .muew text the CI open-file proof writes imports as a user sound
        std::string tmp = std::string("/tmp/muew-open-test-") + std::to_string(getpid());
        system(("mkdir -p " + tmp + "/in " + tmp + "/user").c_str());
        { std::ofstream f(tmp + "/in/Opened Proof.muew"); f << "muew-preset 2\nname Opened Proof\ncategory Lead\nauthor Someone\nfilterCutoff 1234\n"; }
        ui::Library lib; int idx = user::importFile(tmp + "/user", tmp + "/in/Opened Proof.muew", lib);
        ck(idx >= 0 && lib.at(idx).info.name == "Opened Proof" && (int)lib.at(idx).voice.filterCutoff == 1234, "a minimal .muew file imports as a library sound");
        ck(user::importFile(tmp + "/user", tmp + "/in/missing.muew", lib) == -1, "a missing file is refused");
        system(("rm -rf " + tmp).c_str()); }
    printf(failures ? "FAILED\n" : "ALL SESSION 100 TESTS PASSED\n");
    return failures != 0;
}
