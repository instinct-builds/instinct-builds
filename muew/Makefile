CXX ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra

all: build/muew-demo build/muew-tests build/muew-tests-fx build/muew-tests-license build/muew-tests-bank build/muew-tests-wt build/muew-license build/muew-render-preset build/muew-demo-wt build/muew-tests-mod-depth build/muew-demo-mod-depth build/muew-tests-ui build/muew-tests-params build/muew-tests-user build/muew-tests-unison build/muew-tests-matrix build/muew-tests-usertable build/muew-tests-layers build/muew-tests-browser build/muew-tests-dc build/muew-tests-fxrack build/muew-tests-fxdetail build/muew-tests-racklfo build/muew-tests-routecurve build/muew-tests-mseg2 build/muew-tests-lfox build/muew-tests-warpx build/muew-tests-import build/muew-tests-filter1 build/muew-tests-filterroute build/muew-tests-voicex build/muew-tests-perf build/muew-tests-arp

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

build/muew-tests-params: tests/tests_params.cpp src/au_params.h src/ui_model.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_params.cpp

build/muew-tests-user: tests/tests_user_presets.cpp src/user_presets.h src/ui_model.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_user_presets.cpp

build/muew-tests-unison: tests/tests_unison_fx.cpp src/voice.h src/fx.h src/preset.h src/au_params.h src/ui_model.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_unison_fx.cpp

build/muew-tests-matrix: tests/tests_matrix.cpp src/voice.h src/lfo.h src/preset.h src/ui_model.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_matrix.cpp

build/muew-tests-layers: tests/tests_layers.cpp src/layers.h src/voice.h src/preset.h src/au_params.h src/ui_model.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_layers.cpp
build/muew-tests-warpx: tests/tests_warpx.cpp src/oscillator.h src/preset.h src/ui_model.h src/synth.h src/voice.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_warpx.cpp

build/muew-tests-lfox: tests/tests_lfox.cpp src/lfo.h src/preset.h src/ui_model.h src/synth.h src/voice.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_lfox.cpp

build/muew-tests-mseg2: tests/tests_mseg2.cpp src/mseg.h src/preset.h src/ui_model.h src/synth.h src/voice.h src/mod_curve.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_mseg2.cpp

build/muew-tests-routecurve: tests/tests_routecurve.cpp src/fx.h src/preset.h src/ui_model.h src/synth.h src/voice.h src/mod_curve.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_routecurve.cpp

build/muew-tests-racklfo: tests/tests_racklfo.cpp src/fx.h src/preset.h src/ui_model.h src/synth.h src/voice.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_racklfo.cpp

build/muew-tests-fxdetail: tests/tests_fxdetail.cpp src/fx.h src/preset.h src/ui_model.h src/synth.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_fxdetail.cpp

build/muew-tests-fx28: tests/tests_fx28.cpp src/fx.h src/preset.h src/ui_model.h src/au_params.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_fx28.cpp
build/muew-tests-spectral32: tests/tests_spectral32.cpp src/table_recipe.h src/table_history.h src/preset.h src/factory_bank.h src/spectral_process.h src/table_import.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_spectral32.cpp

build/muew-demo-frame37: src/render_demo_frame37.cpp src/frame_tools.h src/synth.h | build
	$(CXX) $(CXXFLAGS) -o $@ src/render_demo_frame37.cpp

build/muew-demo-range38: src/render_demo_range38.cpp src/frame_range.h src/synth.h | build
	$(CXX) $(CXXFLAGS) -o $@ src/render_demo_range38.cpp

build/muew-demo-partial39: src/render_demo_partial39.cpp src/partial_edit.h src/synth.h | build
	$(CXX) $(CXXFLAGS) -o $@ src/render_demo_partial39.cpp

build/muew-demo-partial40: src/render_demo_partial40.cpp src/partial_view.h src/synth.h | build
	$(CXX) $(CXXFLAGS) -o $@ src/render_demo_partial40.cpp

build/muew-demo-span44: src/render_demo_span44.cpp src/spectral_clipboard.h src/synth.h | build
	$(CXX) $(CXXFLAGS) -o $@ src/render_demo_span44.cpp

build/muew-demo-clip43: src/render_demo_clip43.cpp src/spectral_clipboard.h src/synth.h | build
	$(CXX) $(CXXFLAGS) -o $@ src/render_demo_clip43.cpp

build/muew-demo-taper42: src/render_demo_taper42.cpp src/partial_brush.h src/synth.h | build
	$(CXX) $(CXXFLAGS) -o $@ src/render_demo_taper42.cpp

build/muew-demo-brush41: src/render_demo_brush41.cpp src/partial_brush.h src/synth.h | build
	$(CXX) $(CXXFLAGS) -o $@ src/render_demo_brush41.cpp

build/muew-tests-span44: tests/tests_span44.cpp src/spectral_clipboard.h src/table_history.h src/preset.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_span44.cpp

build/muew-tests-clip43: tests/tests_clip43.cpp src/spectral_clipboard.h src/table_history.h src/preset.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_clip43.cpp

build/muew-tests-taper42: tests/tests_taper42.cpp src/partial_brush.h src/table_history.h src/preset.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_taper42.cpp

build/muew-tests-brush41: tests/tests_brush41.cpp src/partial_brush.h src/table_history.h src/preset.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_brush41.cpp

build/muew-tests-partial40: tests/tests_partial40.cpp src/partial_view.h src/table_history.h src/preset.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_partial40.cpp

build/muew-tests-partial39: tests/tests_partial39.cpp src/partial_edit.h src/table_history.h src/preset.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_partial39.cpp

build/muew-tests-range38: tests/tests_range38.cpp src/frame_range.h src/frame_tools.h src/table_history.h src/preset.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_range38.cpp

build/muew-tests-frame37: tests/tests_frame37.cpp src/frame_tools.h src/table_history.h src/preset.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_frame37.cpp

build/muew-tests-live35: tests/tests_live35.cpp src/ui_model.h src/synth.h src/voice.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_live35.cpp
build/muew-tests-live36: tests/tests_live36.cpp src/ui_model.h src/synth.h src/voice.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_live36.cpp

build/muew-tests-lanes34: tests/tests_lanes34.cpp src/au_params.h src/preset.h src/ui_model.h src/factory_bank.h src/synth.h src/voice.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_lanes34.cpp

build/muew-tests-morph33: tests/tests_morph33.cpp src/preset.h src/ui_model.h src/factory_bank.h src/spectral_process.h src/custom_table.h src/synth.h src/voice.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_morph33.cpp

build/muew-tests-spectral31: tests/tests_spectral31.cpp src/spectral_process.h src/table_import.h src/custom_table.h src/wavetable_editor.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_spectral31.cpp

build/muew-tests-hq30: tests/tests_hq30.cpp src/fx.h src/preset.h src/synth.h src/voice.h src/filter.h src/oscillator.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_hq30.cpp

build/muew-tests-quality29: tests/tests_quality29.cpp src/fx.h src/preset.h src/ui_model.h src/synth.h src/voice.h src/envelope.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_quality29.cpp

build/muew-tests-fx27: tests/tests_fx27.cpp src/fx.h src/filter.h src/preset.h src/ui_model.h src/synth.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_fx27.cpp

build/muew-tests-fxrack: tests/tests_fxrack.cpp src/fx.h src/preset.h src/au_params.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_fxrack.cpp

build/muew-tests-dc: tests/tests_dc.cpp src/voice.h src/oscillator.h src/preset.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_dc.cpp
build/muew-tests-browser: tests/tests_browser.cpp src/user_presets.h src/ui_model.h src/preset_bank.h src/preset.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_browser.cpp
build/muew-tests-filterroute: tests/tests_filterroute.cpp src/filter.h src/layers.h src/voice.h src/preset.h src/synth.h src/ui_model.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_filterroute.cpp

build/muew-tests-voicex: tests/tests_voicex.cpp src/voice.h src/preset.h src/synth.h src/ui_model.h src/au_params.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_voicex.cpp

build/muew-tests-perf: tests/tests_perf.cpp src/voice.h src/preset.h src/synth.h src/ui_model.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_perf.cpp

build/muew-tests-arp: tests/tests_arp.cpp src/voice.h src/preset.h src/synth.h src/arp.h src/lfo.h src/fx.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_arp.cpp

build/muew-tests-filter1: tests/tests_filter1.cpp src/filter.h src/voice.h src/preset.h src/synth.h src/ui_model.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_filter1.cpp

build/muew-tests-import: tests/tests_import.cpp src/table_import.h src/custom_table.h src/preset.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_import.cpp

build/muew-tests-usertable: tests/tests_usertable.cpp src/custom_table.h src/voice.h src/oscillator.h src/preset.h src/ui_model.h src/factory_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/tests_usertable.cpp

build/muew-license: src/license_tool.cpp src/license.h | build
	$(CXX) $(CXXFLAGS) -o $@ $<

build/muew-render-preset: src/render_preset.cpp src/preset.h src/preset_bank.h | build
	$(CXX) $(CXXFLAGS) -o $@ $<

test: build/muew-tests build/muew-tests-fx build/muew-tests-license build/muew-tests-bank build/muew-tests-wt build/muew-tests-mod-depth build/muew-tests-ui build/muew-tests-params build/muew-tests-user build/muew-tests-unison build/muew-tests-matrix build/muew-tests-usertable build/muew-tests-layers build/muew-tests-browser build/muew-tests-dc build/muew-tests-fxrack build/muew-tests-fxdetail build/muew-tests-racklfo build/muew-tests-routecurve build/muew-tests-mseg2 build/muew-tests-lfox build/muew-tests-warpx build/muew-tests-import build/muew-tests-filter1 build/muew-tests-fx27 build/muew-tests-fx28 build/muew-tests-quality29 build/muew-tests-hq30 build/muew-tests-spectral31 build/muew-tests-spectral32 build/muew-tests-morph33 build/muew-tests-lanes34 build/muew-tests-live35 build/muew-tests-live36 build/muew-tests-frame37 build/muew-tests-range38 build/muew-tests-partial39 build/muew-tests-partial40 build/muew-tests-brush41 build/muew-tests-taper42 build/muew-tests-clip43 build/muew-tests-span44
	./build/muew-tests
	./build/muew-tests-fx
	./build/muew-tests-license
	./build/muew-tests-bank
	./build/muew-tests-wt
	./build/muew-tests-mod-depth
	./build/muew-tests-ui
	./build/muew-tests-params
	./build/muew-tests-user
	./build/muew-tests-unison
	./build/muew-tests-matrix
	./build/muew-tests-usertable
	./build/muew-tests-import
	./build/muew-tests-filter1
	./build/muew-tests-fx27
	./build/muew-tests-fx28
	./build/muew-tests-quality29
	./build/muew-tests-hq30
	./build/muew-tests-spectral31
	./build/muew-tests-spectral32
	./build/muew-tests-morph33
	./build/muew-tests-lanes34
	./build/muew-tests-live35
	./build/muew-tests-live36
	./build/muew-tests-frame37
	./build/muew-tests-range38
	./build/muew-tests-partial39
	./build/muew-tests-partial40
	./build/muew-tests-brush41
	./build/muew-tests-taper42
	./build/muew-tests-clip43
	./build/muew-tests-span44
	./build/muew-tests-filterroute
	./build/muew-tests-voicex
	./build/muew-tests-perf
	./build/muew-tests-arp
	./build/muew-tests-layers
	./build/muew-tests-browser
	./build/muew-tests-dc
	./build/muew-tests-fxrack
	./build/muew-tests-fxdetail
	./build/muew-tests-racklfo
	./build/muew-tests-routecurve
	./build/muew-tests-mseg2
	./build/muew-tests-lfox
	./build/muew-tests-warpx

render: build/muew-demo
	./build/muew-demo

clean:
	rm -rf build out

.PHONY: all test render clean
