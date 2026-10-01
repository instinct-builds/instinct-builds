#!/usr/bin/env python3
"""Deterministic launch-race tests, without launching Chrome or the gallery."""
import ast, pathlib, tempfile, time, unittest
source = pathlib.Path(__file__).with_name('reviewer-drafts.py').read_text()
tree = ast.parse(source)
function = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'wait_for_debug_port')
namespace = {'time': time}
exec(compile(ast.Module(body=[function], type_ignores=[]), str(__file__), 'exec'), namespace)
wait = namespace['wait_for_debug_port']

class DebugPortTests(unittest.TestCase):
    def run_case(self, states, exit_code=None, timeout=.2):
        with tempfile.TemporaryDirectory() as folder:
            port = pathlib.Path(folder)/'DevToolsActivePort'
            stderr = pathlib.Path(folder)/'stderr'
            stderr.write_text('launch diagnostic marker')
            class Process:
                returncode = exit_code
                calls = 0
                def poll(self):
                    state = states[min(self.calls, len(states)-1)]
                    self.calls += 1
                    if state is None: port.unlink(missing_ok=True)
                    else: port.write_text(state)
                    return exit_code
            return wait(Process(), port, stderr, time.monotonic()+timeout, .001)
    def test_missing_then_empty_then_valid(self):
        self.assertEqual(self.run_case([None, '', '49123\n/devtools/browser/test']), 49123)
    def test_partial_invalid_and_out_of_range_then_valid(self):
        self.assertEqual(self.run_case(['\n', 'not-a-port', '0', '70000', '49124']), 49124)
    def test_empty_timeout_has_diagnostic(self):
        with self.assertRaisesRegex(TimeoutError, 'exists but is empty; stderr tail: launch diagnostic marker'):
            self.run_case([''], timeout=.005)
    def test_invalid_timeout_has_diagnostic(self):
        with self.assertRaisesRegex(TimeoutError, 'invalid first line'):
            self.run_case(['bad'], timeout=.005)
    def test_exited_process_has_diagnostic(self):
        with self.assertRaisesRegex(RuntimeError, 'exited 17 before DevTools.*launch diagnostic marker'):
            self.run_case([''], exit_code=17)

if __name__ == '__main__': unittest.main()
