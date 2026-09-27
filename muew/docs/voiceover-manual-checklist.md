# MUEW external accessibility check

The in-process AppKit tree test from 0.81.0 does not prove VoiceOver or AX IPC. On macOS, grant the external test client Accessibility permission in System Settings > Privacy & Security > Accessibility and restart it. Launch the standalone with the full preset browser open. In Accessibility Inspector or VoiceOver:

1. Confirm native Search and a distinct named Preset results list appear in window order. Each visible result has its exact name/category, position and separate proposed/loaded states. Confirm the frame follows the visible row.
2. Focus and traverse rows without pressing. No sound changes and no notes start. Type a query in native Search; confirm list children reflect the filter. Hold a reference to a row filtered away, then confirm its press refuses to load, including after the slug reappears.
3. Sort and inspect position/slug changes. Use an arrow to propose a row, confirm proposed yes and loaded no. Deliberately press that row and confirm the exact sound loads, proposed clears and loaded changes. Closing browser removes the list.
4. In a real AU host, confirm the host retains its keyboard shortcuts and the editor's browser can be inspected separately. Check save/import/export native dialogs and focus return manually; these and other custom-drawn controls remain outside the browser pilot.

Record macOS version, client and host versions, TCC permission state, AX error codes, actual speech/traversal and any missing controls. A failed or blocked CI IPC probe is not a VoiceOver pass.
