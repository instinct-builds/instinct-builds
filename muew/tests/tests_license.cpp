// tests_license.cpp - licensing: signed keys, 3-device activation, tamper checks.
#include "../src/license.h"
#include <cstdio>
#include <fstream>

using namespace muew::license;

static int g_fail = 0;
static void check(bool cond, const char* name) {
    if (cond) printf("ok:   %s\n", name);
    else { printf("FAIL: %s\n", name); ++g_fail; }
}

static const char* kSecret = "muew-test-vendor-secret";
static const char* kStore = "out/test-license-store.txt";

int main() {
    // --- hash primitives against published test vectors ---
    {
        auto h = Sha256::hash("abc");
        check(toHex(h.data(), h.size()) ==
              "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
              "sha256 matches the published 'abc' vector");
    }
    {
        auto h = Sha256::hash("");
        check(toHex(h.data(), h.size()) ==
              "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
              "sha256 matches the published empty-string vector");
    }
    {
        // RFC 4231 test case 1: key = 0x0b x 20, data = "Hi There"
        std::array<uint8_t, 32> h = hmacSha256(std::string(20, '\x0b'), "Hi There");
        check(toHex(h.data(), h.size()) ==
              "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
              "hmac-sha256 matches RFC 4231 test case 1");
    }

    // --- key generation and validation ---
    std::string key = generateKey(kSecret, 3, 1, 21000);
    check(key.rfind("MUEW3-", 0) == 0, "generated key carries the MUEW3 prefix");

    Key k;
    std::string err;
    check(validateKey(key, kSecret, k, err), "generated key validates");
    check(k.maxDevices == 3 && k.features == 1 && k.issueDays == 21000,
          "key fields round-trip exactly");
    check(k.encoded == key, "validation returns the canonical key text");

    {
        std::string lower = key;
        for (auto& c : lower) if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
        Key k2;
        check(validateKey(lower, kSecret, k2, err), "lowercase key text validates");
    }
    {
        std::string squashed;
        for (char c : key) if (c != '-') squashed.push_back(c);
        Key k2;
        check(validateKey(squashed, kSecret, k2, err), "key text without dashes validates");
    }
    {
        std::string bad = key;
        size_t pos = bad.find_last_not_of('-');
        bad[pos] = (bad[pos] == 'A') ? 'B' : 'A';
        Key k2;
        check(!validateKey(bad, kSecret, k2, err), "a single altered character is rejected");
    }
    {
        Key k2;
        check(!validateKey(key, "the-wrong-secret", k2, err),
              "the wrong vendor secret is rejected");
    }
    {
        Key k2;
        check(!validateKey("SERUM2-AAAA-AAAA-AAAA", kSecret, k2, err),
              "a foreign key prefix is rejected");
    }
    check(generateKey(kSecret, 3, 1, 21000) != key, "two generated keys are unique");

    // --- activation flow: the 3-device limit ---
    std::remove(kStore);
    ActivationStore store(kStore);
    check(store.load(kSecret, err), "missing store file loads as a fresh store");
    check(store.activate(k, kSecret, "dev-A", "Studio Mac", err) == ActivateResult::Ok,
          "first device activates");
    check(store.slotsUsed() == 1, "one slot is used after first activation");
    check(store.activate(k, kSecret, "dev-A", "Studio Mac", err) == ActivateResult::AlreadyActive,
          "re-activating the same device is idempotent");
    check(store.activate(k, kSecret, "dev-B", "Laptop", err) == ActivateResult::Ok &&
          store.activate(k, kSecret, "dev-C", "Work iMac", err) == ActivateResult::Ok,
          "second and third devices activate");
    check(store.slotsUsed() == 3, "all three slots are used");
    check(store.activate(k, kSecret, "dev-D", "Fourth Box", err) == ActivateResult::LimitReached,
          "the fourth device hits the 3-device limit");
    check(store.isActivatedFor("dev-A", kSecret) && !store.isActivatedFor("dev-X", kSecret),
          "activation status is per-device");

    // --- deactivation frees a slot ---
    check(store.deactivate("dev-B", kSecret), "deactivation succeeds for an active device");
    check(store.slotsUsed() == 2, "deactivation frees a slot");
    check(store.activate(k, kSecret, "dev-D", "Fourth Box", err) == ActivateResult::Ok,
          "the freed slot can be reused");

    // --- persistence ---
    {
        ActivationStore reloaded(kStore);
        check(reloaded.load(kSecret, err), "store reloads from disk");
        check(reloaded.slotsUsed() == 3, "slots survive a reload");
        check(reloaded.isActivatedFor("dev-A", kSecret) &&
              reloaded.isActivatedFor("dev-D", kSecret),
              "activations survive a reload");
        check(reloaded.encodedKey() == key, "the stored key text survives a reload");
    }

    // --- tamper detection ---
    {
        std::ofstream f(kStore, std::ios::app);
        f << "activation deadbeef deadbeef 0 Forged\n";
    }
    {
        ActivationStore forged(kStore);
        check(!forged.load(kSecret, err), "a hand-added activation line is detected");
    }

    // --- a store bound to one key rejects another key ---
    {
        std::remove(kStore);
        ActivationStore s2(kStore);
        s2.load(kSecret, err);
        s2.activate(k, kSecret, "dev-A", "Studio Mac", err);
        Key other;
        std::string otherKey = generateKey(kSecret, 3, 1, 21000);
        validateKey(otherKey, kSecret, other, err);
        check(s2.activate(other, kSecret, "dev-Z", "Other", err) == ActivateResult::InvalidKey,
              "a store bound to one key rejects a different key");
    }

    // --- a 1-device key enforces its own limit ---
    {
        Key solo;
        std::string soloKey = generateKey(kSecret, 1, 1, 21000);
        validateKey(soloKey, kSecret, solo, err);
        std::remove(kStore);
        ActivationStore s3(kStore);
        s3.load(kSecret, err);
        s3.activate(solo, kSecret, "dev-A", "Only Mac", err);
        check(s3.activate(solo, kSecret, "dev-B", "Second", err) == ActivateResult::LimitReached,
              "a 1-device key stops at one device");
    }

    check(!defaultDeviceId().empty() && defaultDeviceId() == defaultDeviceId(),
          "default device id is stable and non-empty");

    std::remove(kStore);
    if (g_fail == 0) { printf("\nALL LICENSE TESTS PASSED\n"); return 0; }
    printf("\n%d LICENSE TEST(S) FAILED\n", g_fail);
    return 1;
}
