// license_tool.cpp - muew-license CLI: generate, validate, activate, status.
//
// The vendor secret comes from MUEW_VENDOR_SECRET. A development fallback is
// compiled in so the tool works out of the box; production builds must set
// the real secret (and embed only the matching public half in the plugin).
#include "license.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

using namespace muew::license;

static std::string vendorSecret() {
    const char* s = getenv("MUEW_VENDOR_SECRET");
    if (s && *s) return s;
    fprintf(stderr, "note: MUEW_VENDOR_SECRET not set; using the built-in development secret\n");
    return "muew-dev-secret-change-me";
}

static std::string defaultStorePath() {
    const char* home = getenv("HOME");
    std::string dir = home ? home : ".";
    std::string path = dir + "/.muew";
    std::string cmd = "mkdir -p \"" + dir + "/.muew\"";
    if (system(cmd.c_str()) != 0) { /* best effort */ }
    return path + "/license";
}

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("muew-license <command>\n"
               "  generate [maxDevices]      create a new license key\n"
               "  validate <key>             check a key's signature and fields\n"
               "  activate <key> [store]     activate this device (default ~/.muew/license)\n"
               "  deactivate [store]         remove this device's activation\n"
               "  status [store]             show slots used and devices\n");
        return 1;
    }
    std::string secret = vendorSecret();
    std::string cmd = argv[1];
    std::string err;

    if (cmd == "generate") {
        int maxDev = argc >= 3 ? atoi(argv[2]) : 3;
        if (maxDev < 1 || maxDev > 99) { fprintf(stderr, "maxDevices must be 1..99\n"); return 1; }
        printf("%s\n", generateKey(secret, (uint8_t)maxDev).c_str());
        return 0;
    }
    if (cmd == "validate") {
        if (argc < 3) { fprintf(stderr, "validate needs a key\n"); return 1; }
        Key k;
        if (!validateKey(argv[2], secret, k, err)) { fprintf(stderr, "invalid: %s\n", err.c_str()); return 1; }
        printf("valid MUEW3 key: maxDevices=%d features=%u issued=day-%u id=%s\n",
               k.maxDevices, k.features, k.issueDays, keyId(k).c_str());
        return 0;
    }
    std::string storePath = defaultStorePath();
    if (cmd == "activate") {
        if (argc < 3) { fprintf(stderr, "activate needs a key\n"); return 1; }
        if (argc >= 4) storePath = argv[3];
        Key k;
        if (!validateKey(argv[2], secret, k, err)) { fprintf(stderr, "invalid: %s\n", err.c_str()); return 1; }
        ActivationStore store(storePath);
        if (!store.load(secret, err)) { fprintf(stderr, "%s\n", err.c_str()); return 1; }
        std::string devId = defaultDeviceId(), devLabel = defaultDeviceLabel();
        auto r = store.activate(k, secret, devId, devLabel, err);
        if (r != ActivateResult::Ok && r != ActivateResult::AlreadyActive) {
            fprintf(stderr, "activation failed: %s\n", toString(r)); return 1;
        }
        printf("%s (%d/%d slots used on %s)\n", toString(r), store.slotsUsed(),
               k.maxDevices, devLabel.c_str());
        return 0;
    }
    if (cmd == "deactivate") {
        if (argc >= 3) storePath = argv[2];
        ActivationStore store(storePath);
        if (!store.load(secret, err)) { fprintf(stderr, "%s\n", err.c_str()); return 1; }
        if (!store.deactivate(defaultDeviceId(), secret)) { fprintf(stderr, "this device was not activated\n"); return 1; }
        printf("deactivated (%d slots used)\n", store.slotsUsed());
        return 0;
    }
    if (cmd == "status") {
        if (argc >= 3) storePath = argv[2];
        ActivationStore store(storePath);
        if (!store.load(secret, err)) { fprintf(stderr, "%s\n", err.c_str()); return 1; }
        if (store.keyId().empty()) { printf("no license on this device\n"); return 0; }
        printf("key id: %s\nslots used: %d\n", store.keyId().c_str(), store.slotsUsed());
        for (const auto& a : store.activations())
            printf("  - %s (activated day %u)%s\n", a.label.c_str(), a.firstSeenDays,
                   store.isActivatedFor(defaultDeviceId(), secret) &&
                   a.deviceHash == sha256Hex(defaultDeviceId()) ? "  <- this device" : "");
        return 0;
    }
    fprintf(stderr, "unknown command: %s\n", cmd.c_str());
    return 1;
}
