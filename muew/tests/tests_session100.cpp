// 0.100.0 standalone session encode/decode.
#include "../src/session_state.h"
#include "../src/factory_bank.h"
#include <cstdio>
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
    printf(failures ? "FAILED\n" : "ALL SESSION 100 TESTS PASSED\n");
    return failures != 0;
}
