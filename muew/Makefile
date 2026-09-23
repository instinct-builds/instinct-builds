CXX ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra

all: build/muew-demo build/muew-tests build/muew-tests-fx build/muew-tests-license build/muew-tests-bank build/muew-tests-wt build/muew-license build/muew-render-preset build/muew-demo-wt build/muew-tests-mod-depth build/muew-demo-mod-depth build/muew-tests-ui

build:
	mkdir -p build out

build/muew-demo: src/render_demo.cpp | build
	$(CXX) $(CXXFLAGS) -o $@ $<

build/muew-tests: tests/tests.cpp | build
	$(CXX) $(CXXFLAGS) -o $@ $<

build/muew-tests-fx: tests/tests_fx.cpp | build
	$(CXX) $(CXXFLAGS) -o $@ $<

build/muew-tests-license: tests/tests_license.cpp src/license.h | build
	$(CXX) $(CXXFLAGS) -o $@ $<

build/muew-tests-bank: tests/tests_bank.cpp src/preset.h src/preset_bank.h src/factory_bank.h presets/bank.txt | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_bank.cpp

build/muew-tests-wt: tests/tests_wavetable_editor.cpp src/wavetable_editor.h src/wavetable.h src/synth.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_wavetable_editor.cpp

build/muew-demo-wt: src/render_demo_wt.cpp src/wavetable_editor.h | build
	$(CXX) $(CXXFLAGS) -o $@ src/render_demo_wt.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

build/muew-tests-mod-depth: tests/tests_modulation_depth.cpp src/mseg.h src/oscillator.h src/voice.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_modulation_depth.cpp

build/muew-demo-mod-depth: src/render_demo_mod_depth.cpp src/mseg.h src/oscillator.h src/voice.h | build
	$(CXX) $(CXXFLAGS) -o $@ src/render_demo_mod_depth.cpp

build/muew-tests-ui: tests/tests_ui_model.cpp src/ui_model.h src/factory_bank.h src/preset_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_ui_model.cpp

build/muew-license: src/license_tool.cpp src/license.h | build
	$(CXX) $(CXXFLAGS) -o $@ $<

build/muew-render-preset: src/render_preset.cpp src/preset.h src/preset_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ $<

test: build/muew-tests build/muew-tests-fx build/muew-tests-license build/muew-tests-bank build/muew-tests-wt build/muew-tests-mod-depth build/muew-tests-ui
	./build/muew-tests
	./build/muew-tests-fx
	./build/muew-tests-license
	./build/muew-tests-bank
	./build/muew-tests-wt
	./build/muew-tests-mod-depth
	./build/muew-tests-ui

render: build/muew-demo
	./build/muew-demo

clean:
	rm -rf build out

.PHONY: all test render clean
