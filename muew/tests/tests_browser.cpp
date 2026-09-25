// tests_browser.cpp - 0.11.0 preset browser v2: descriptions round-trip,
// character tags, banks (Factory / User / Imported), sort orders, ratings,
// Import, and the expanded factory bank.
#include "../src/user_presets.h"
#include <cstdio>
#include <cstdlib>

using namespace muew;
static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }

int main() {
    namespace fs = std::filesystem;
    const auto& bank = factoryPresets();
    check(kFactoryPresetCount == 104 && (int)bank.size() == 104, "factory bank has 104 presets");

    // Every factory preset: description, at least one character tag, exact round trip.
    bool desc = true, chars = true, rt = true;
    for (int i = 0; i < kFactoryPresetCount; ++i) {
        const Preset& p = bank[i];
        if (p.info.description.size() < 20) desc = false;
        bool any = false;
        for (const auto& t : characterTags()) any = any || p.hasTag(t);
        if (!any) chars = false;
        if (p.serialize() != std::string(kFactoryPresetTexts[i].text)) rt = false;
    }
    check(desc, "every factory preset has a description");
    check(chars, "every factory preset carries a character tag");
    check(rt, "factory files (with desc lines) round-trip byte-identical");
    std::map<std::string, int> cats;
    for (const auto& p : bank) cats[p.info.category]++;
    bool spread = true;
    for (const auto& c : factoryCategories()) spread = spread && cats[c] >= 8;
    check(spread, "every category has at least 8 factory presets");

    // desc is optional: a preset without one serializes no desc line.
    Preset plain = bank[0]; plain.info.description.clear();
    check(plain.serialize().find("\ndesc ") == std::string::npos, "no desc line when empty");
    Preset nl = bank[0]; nl.info.description = "two\nlines";
    Preset back; back.parse(nl.serialize());
    check(back.info.description == "two lines" && back.voice.filterCutoff == nl.voice.filterCutoff, "newlines in a description flatten to one line");

    ui::Library lib;
    std::set<std::string> favs;
    // Character tags: AND across selected tags.
    PresetFilter f; f.tags = {"dark"};
    auto dark = ui::visiblePresets(f, favs, lib);
    f.tags = {"dark", "aggressive"};
    auto both = ui::visiblePresets(f, favs, lib);
    bool sub = !both.empty() && both.size() < dark.size();
    for (int i : both) sub = sub && lib.at(i).hasTag("dark") && lib.at(i).hasTag("aggressive");
    check(sub, "character tags narrow with AND");
    f = {}; f.query = "kick";
    auto q = ui::visiblePresets(f, favs, lib);
    check(!q.empty() && std::find(q.begin(), q.end(), ui::indexOfSlug("deep-house-sub")) != q.end(), "search matches descriptions");
    f.query = "mUEw fAcToRy";
    check((int)ui::visiblePresets(f, favs, lib).size() == 104, "search matches author, case-insensitive");

    // Sort orders.
    auto all = ui::visiblePresets({}, favs, lib);
    auto byName = all; ui::sortPresets(byName, ui::SortName, lib, {});
    bool nameOk = true;
    for (size_t i = 1; i < byName.size(); ++i) nameOk = nameOk && muewLower(lib.at(byName[i - 1]).info.name) <= muewLower(lib.at(byName[i]).info.name);
    check(nameOk && byName.size() == all.size(), "name sort is alphabetical");
    auto byCat = all; ui::sortPresets(byCat, ui::SortCategory, lib, {});
    check(lib.at(byCat.front()).info.category == "Bass" && lib.at(byCat.back()).info.category == "FX", "type sort follows the category order");
    ui::Ratings r;
    ui::setRating(r, "pluck", 3); ui::setRating(r, "warm-pad", 5); ui::setRating(r, "sub-bass", 3);
    auto byRate = all; ui::sortPresets(byRate, ui::SortRating, lib, r);
    check(byRate[0] == ui::indexOfSlug("warm-pad") && byRate[1] == ui::indexOfSlug("pluck") && byRate[2] == ui::indexOfSlug("sub-bass")
          && byRate[3] == 0, "rating sort: best first, ties and unrated keep bank order");
    ui::setRating(r, "pluck", 3);
    check(ui::ratingOf(r, "pluck") == 0 && ui::ratingOf(r, "warm-pad") == 5, "clicking the set star clears the rating");
    auto sorted = ui::visiblePresets({}, favs, lib, r, ui::SortRating);
    auto again = all; ui::sortPresets(again, ui::SortRating, lib, r);
    check(sorted == again && sorted[0] == ui::indexOfSlug("warm-pad") && sorted[1] == ui::indexOfSlug("sub-bass"), "filter + sort helper");

    // Banks and Import.
    fs::path dir = fs::temp_directory_path() / ("muew-browser-test-" + std::to_string(std::rand()));
    fs::path ext = fs::temp_directory_path() / ("muew-browser-ext-" + std::to_string(std::rand()) + ".muew");
    fs::remove_all(dir);
    Preset mine = bank[3]; mine.voice.filterCutoff = 1234;
    int saved = user::save(dir.string(), mine, "My Pluck", lib);
    Preset theirs = bank[7]; theirs.info.name = "Friend Pad"; theirs.info.author = "Sam"; theirs.info.description = "From a friend.";
    user::exportTo(ext.string(), theirs);
    int imp = user::importFile(dir.string(), ext.string(), lib);
    saved = lib.indexOfName("My Pluck");
    check(imp >= kFactoryPresetCount && lib.at(imp).info.author == "Sam" && lib.at(imp).info.description == "From a friend."
          && lib.at(imp).voice.filterCutoff == theirs.voice.filterCutoff, "Import copies the file into the user folder as authored");
    check(ui::bankOf(lib, 0) == ui::BankFactory && ui::bankOf(lib, saved) == ui::BankUser && ui::bankOf(lib, imp) == ui::BankImported,
          "banks: factory, saved in MUEW, imported");
    PresetFilter bf; bf.bank = ui::BankImported;
    auto impOnly = ui::visiblePresets(bf, favs, lib);
    bf.bank = ui::BankUserFolder;
    auto folder = ui::visiblePresets(bf, favs, lib);
    bf.bank = ui::BankFactory;
    check(impOnly.size() == 1 && impOnly[0] == imp && folder.size() == 2 && (int)ui::visiblePresets(bf, favs, lib).size() == 104,
          "bank filter: Imported, user folder, Factory");
    check(ui::visiblePresets({}, favs, lib, true) == folder, "legacy userOnly equals the user folder bank");
    Preset anon = bank[1]; anon.info.author = "User"; anon.info.name = "Pluck";
    user::exportTo(ext.string(), anon);
    int imp2 = user::importFile(dir.string(), ext.string(), lib);
    check(imp2 >= 0 && lib.at(imp2).info.author == "Imported" && lib.at(imp2).info.name == "Pluck 2",
          "imported files never pose as User presets or shadow factory names");
    check(user::importFile(dir.string(), (dir / "missing.muew").string(), lib) == -1, "Import of a missing file fails cleanly");
    fs::remove_all(dir); fs::remove(ext);

    if (g_fail == 0) { printf("\nALL BROWSER TESTS PASSED\n"); return 0; }
    printf("\n%d BROWSER TEST(S) FAILED\n", g_fail); return 1;
}
