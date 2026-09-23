// User preset tests: save/load round trips, naming, library indexing, filtering.
#include "../src/user_presets.h"
#include <cstdio>
#include <cstdlib>

using namespace muew;
static int failures = 0;
static void check(bool ok, const char* what) { std::printf("%s %s\n", ok ? "ok:  " : "FAIL:", what); if (!ok) ++failures; }

int main() {
    namespace fs = std::filesystem;
    fs::path dir = fs::temp_directory_path() / ("muew-user-test-" + std::to_string(std::rand()));
    fs::remove_all(dir);
    ui::Library lib;
    check(user::load(dir.string(), lib) == 0 && lib.count() == kFactoryPresetCount, "missing folder means no user presets");

    Preset edited = factoryPresets()[ui::indexOfSlug("rising-tide")];
    edited.voice.filterCutoff = 2345; edited.voice.macros[0] = 0.4; edited.voice.macros[3] = 0.9;
    int idx = user::save(dir.string(), edited, "My Riser", lib);
    check(idx == kFactoryPresetCount && lib.isUser(idx) && lib.factoryNumber(idx) == -1, "saved preset is appended after the factory bank");
    const Preset& got = lib.at(idx);
    check(got.info.name == "My Riser" && got.info.author == "User" && got.voice.filterCutoff == 2345
          && got.voice.macros[0] == 0.4 && got.voice.macros[3] == 0.9 && got.routes.size() == edited.routes.size(),
          "saved sound, macros and routes load back exactly");
    check(fs::exists(dir / "My Riser.muew"), "file named after the preset");

    // Name collisions: with a user preset and with a factory preset.
    int idx2 = user::save(dir.string(), edited, "My Riser", lib);
    int idx3 = user::save(dir.string(), edited, "Warm Pad", lib);
    check(idx2 >= 0 && lib.at(idx2).info.name == "My Riser 2", "duplicate user name gets a number");
    check(idx3 >= 0 && lib.at(idx3).info.name == "Warm Pad 2" && lib.indexOfName("Warm Pad") == 7, "factory names are never shadowed");
    check(lib.count() == kFactoryPresetCount + 3, "library count");

    // Unsafe names become safe file names.
    int idx4 = user::save(dir.string(), edited, "../evil/:name*", lib);
    check(idx4 >= 0 && fs::exists(dir / "evilname.muew") && !fs::exists(dir.parent_path() / "evil"), "path characters are stripped from file names");

    // A fresh library (e.g. the AU in another process) sees the same presets.
    ui::Library other;
    check(user::load(dir.string(), other) == 4 && other.indexOfName("My Riser") >= kFactoryPresetCount, "presets are shared through the folder");

    // Browser filtering: User view, category chips and search include user presets.
    auto userOnly = ui::visiblePresets({}, {}, other, true);
    check(userOnly.size() == 4 && userOnly.front() >= kFactoryPresetCount, "User view lists only saved presets");
    PresetFilter fx; fx.category = "FX";
    auto fxList = ui::visiblePresets(fx, {}, other);
    check(std::find(fxList.begin(), fxList.end(), other.indexOfName("My Riser")) != fxList.end(), "user presets keep their category");
    PresetFilter q; q.query = "riser";
    check(ui::visiblePresets(q, {}, other).size() >= 3, "search finds user presets");
    std::set<std::string> favs{other.slug(other.indexOfName("My Riser"))};
    PresetFilter fav; fav.favoritesOnly = true;
    check(ui::visiblePresets(fav, favs, other).size() == 1 && other.slug(other.indexOfName("My Riser")) == "user/My Riser.muew",
          "user presets can be favorites");

    // Garbage files are skipped, export writes a loadable file.
    user::writeText(dir / "broken.muew", "not a preset");
    check(user::load(dir.string(), other) == 4, "unreadable files are skipped");
    fs::path out = dir / "export" ;
    fs::create_directories(out);
    check(user::exportTo((out / "share.muew").string(), edited), "export writes a file");
    std::string text; Preset back;
    check(user::readText(out / "share.muew", text) && back.parse(text) && back.voice.macros[3] == 0.9, "exported file loads");

    fs::remove_all(dir);
    if (failures) { std::printf("%d USER PRESET TEST(S) FAILED\n", failures); return 1; }
    std::printf("ALL USER PRESET TESTS PASSED\n");
    return 0;
}
