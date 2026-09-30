// Independent fail-fast guard for desktop/host proofs. Never uses AppKit's
// main queue or run loop: a nested modal loop cannot suppress this deadline.
#pragma once
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <thread>
namespace muew_proof {
inline std::atomic<const char*> phase{"boot"};
inline void Phase(const char* name) {
    phase.store(name);
    std::fprintf(stderr,"proof phase: %s\n",name);
    std::fflush(stderr);
}
inline void Watchdog(const char* proof, int seconds) {
    std::thread([proof,seconds] {
        std::this_thread::sleep_for(std::chrono::seconds(seconds));
        std::fprintf(stderr,"FAIL: HARD WATCHDOG %s exceeded %ds, phase=%s\n",proof,seconds,phase.load());
        std::fflush(stderr);
        std::_Exit(124);
    }).detach();
}
}
