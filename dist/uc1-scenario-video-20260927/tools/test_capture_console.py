"""Real-subprocess console lifecycle tests; no MATLAB, ADI, or network calls."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


TOOLS = Path(__file__).resolve().parent


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.output = self.root / 'console.jsonl'
        self.processes = []

    def tearDown(self):
        for process in self.processes:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)
        self.temp.cleanup()

    def launch(self, code, *args, fast_shutdown=False):
        runner = [sys.executable, '-u', str(TOOLS / 'capture_console.py')]
        if fast_shutdown:
            runner = [sys.executable, '-u', '-c',
                      'import capture_console as c; '
                      'c.INTERRUPT_GRACE_SECONDS=.25; '
                      'c.TERMINATE_GRACE_SECONDS=.25; '
                      'c.DESCENDANT_GRACE_SECONDS=.25; '
                      'raise SystemExit(c.main())']
        process = subprocess.Popen(
            runner + ['--output', str(self.output), '--', sys.executable, '-u', '-c', code, *args],
            cwd=TOOLS, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding='utf-8', env={**os.environ, 'PYTHONIOENCODING': 'utf-8'})
        self.processes.append(process)
        return process

    def wait_file(self, path):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if path.exists() and path.stat().st_size:
                return
            time.sleep(.025)
        self.fail(f'Timed out waiting for {path.name}')

    def status(self):
        return json.loads(self.output.with_suffix('.status.json').read_text(encoding='utf-8'))

    def test_success_preserves_output_without_completion_footer(self):
        code = "import sys; print('ready'); print(); print('error detail', file=sys.stderr); sys.stdout.write('final partial line')"
        process = self.launch(code)
        out, err = process.communicate(timeout=10)
        expected = 'ready\n\nerror detail\nfinal partial line'
        self.assertEqual(process.returncode, 0)
        self.assertEqual(out, expected)
        self.assertEqual(err, '')
        self.assertEqual(self.output.with_suffix('.txt').read_text(encoding='utf-8'), expected)
        records = [json.loads(line) for line in self.output.read_text(encoding='utf-8').splitlines()]
        self.assertEqual([record['text'] for record in records], ['ready', '', 'error detail', 'final partial line'])
        self.assertEqual(self.status()['exit_code'], 0)
        self.assertEqual(self.status()['child_exit_code'], 0)
        self.assertIsNone(self.status()['signal'])

    def test_failure_retains_code_and_child_error(self):
        process = self.launch("import sys; print('actual child failure', file=sys.stderr); raise SystemExit(7)")
        out, err = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 7)
        self.assertEqual(out, 'actual child failure\n')
        self.assertIn('exit code 7', err)
        self.assertEqual(self.status()['exit_code'], 7)
        self.assertNotIn('PROCESS EXIT', self.output.read_text(encoding='utf-8'))

    def test_running_output_is_flushed_before_child_finishes(self):
        gate = self.root / 'continue'
        code = "import pathlib, sys, time; p=pathlib.Path(sys.argv[1]); print('listener active', flush=True)\nwhile not p.exists(): time.sleep(.025)\nprint('operator stopped')"
        process = self.launch(code, str(gate))
        self.wait_file(self.output)
        self.assertIsNone(process.poll())
        self.assertIn('listener active', self.output.with_suffix('.txt').read_text(encoding='utf-8'))
        self.assertFalse(self.output.with_suffix('.status.json').exists())
        gate.touch()
        out, _ = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0)
        self.assertEqual(out, 'listener active\noperator stopped\n')

    @unittest.skipUnless(os.name == 'posix', 'POSIX signal and process-group behavior')
    def test_ctrl_c_preserves_signal_after_graceful_child_cleanup(self):
        code = "import signal, sys, time\ndef stop(s,f):\n print('child cleanup complete', flush=True)\n sys.exit(0)\nsignal.signal(signal.SIGINT, stop)\nprint('ready', flush=True)\nwhile True: time.sleep(.05)"
        process = self.launch(code)
        self.wait_file(self.output)
        process.send_signal(signal.SIGINT)
        out, err = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 130)
        self.assertIn('child cleanup complete', out)
        self.assertEqual(err, '')
        self.assertEqual(self.status()['signal'], signal.SIGINT)
        self.assertEqual(self.status()['child_exit_code'], 0)

    @unittest.skipUnless(os.name == 'posix', 'POSIX terminal hangup and process groups')
    def test_terminal_hangup_cleans_up_background_process(self):
        pid_path = self.root / 'descendant.pid'
        grandchild = "import os,pathlib,signal,sys,time; signal.signal(signal.SIGHUP,signal.SIG_IGN); signal.signal(signal.SIGTERM,signal.SIG_IGN); pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)"
        code = ("import signal,subprocess,sys,time\n"
                "def stop(s,f):\n print('SSH hangup received',flush=True)\n sys.exit(0)\n"
                "signal.signal(signal.SIGHUP,stop)\n"
                f"subprocess.Popen([sys.executable,'-u','-c',{grandchild!r},sys.argv[1]])\n"
                "print('ready',flush=True)\nwhile True: time.sleep(.05)")
        process = self.launch(code, str(pid_path), fast_shutdown=True)
        self.wait_file(pid_path)
        self.wait_file(self.output)
        process.send_signal(signal.SIGHUP)
        out, err = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 129)
        self.assertIn('SSH hangup received', out)
        self.assertEqual(err, '')
        self.assertEqual(self.status()['signal'], signal.SIGHUP)
        self.assertEqual(self.status()['child_exit_code'], 0)
        self.assert_process_stopped(int(pid_path.read_text()))

    @unittest.skipUnless(sys.platform.startswith('linux'), 'Linux orphan adoption and pidfd cleanup')
    def test_hangup_cleans_up_adopted_detached_grandchild(self):
        pid_path = self.root / 'detached.pid'
        grandchild = "import os,pathlib,signal,sys,time; signal.signal(signal.SIGHUP,signal.SIG_IGN); signal.signal(signal.SIGTERM,signal.SIG_IGN); pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)"
        intermediate = ("import subprocess,sys; "
                        f"subprocess.Popen([sys.executable,'-u','-c',{grandchild!r},sys.argv[1]], start_new_session=True)")
        code = ("import subprocess,sys,time; "
                f"subprocess.run([sys.executable,'-u','-c',{intermediate!r},sys.argv[1]],check=True); "
                "print('listener active',flush=True); time.sleep(60)")
        process = self.launch(code, str(pid_path), fast_shutdown=True)
        self.wait_file(pid_path)
        self.wait_file(self.output)
        descendant = int(pid_path.read_text())
        # The intermediate launcher exits while the main child still runs.
        # The detached listener must be adopted by capture, not system init.
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            stat = Path(f'/proc/{descendant}/stat').read_text().rsplit(')', 1)[1].split()
            if int(stat[1]) == process.pid:
                break
            time.sleep(.025)
        self.assertEqual(int(stat[1]), process.pid)
        self.assertEqual(int(stat[2]), descendant)  # It escaped the main group.
        process.send_signal(signal.SIGHUP)
        _, err = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 129)
        self.assertEqual(err, '')
        self.assertEqual(self.status()['signal'], signal.SIGHUP)
        self.assertTrue(self.status()['descendant_cleanup_complete'])
        self.assert_process_stopped(descendant)
        self.assertFalse(Path(f'/proc/{descendant}').exists(), 'Adopted child was not reaped')

    @unittest.skipUnless(os.name == 'posix', 'POSIX signal and process-group behavior')
    def test_termination_kills_unresponsive_descendant_within_bound(self):
        pid_path = self.root / 'descendant.pid'
        grandchild = "import os,pathlib,signal,sys,time; signal.signal(signal.SIGINT,signal.SIG_IGN); signal.signal(signal.SIGTERM,signal.SIG_IGN); pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)"
        code = ("import signal,subprocess,sys,time; signal.signal(signal.SIGINT,signal.SIG_IGN); signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                f"subprocess.Popen([sys.executable,'-u','-c',{grandchild!r},sys.argv[1]]); "
                "print('ready',flush=True); time.sleep(60)")
        process = self.launch(code, str(pid_path), fast_shutdown=True)
        self.wait_file(pid_path)
        descendant = int(pid_path.read_text())
        started = time.monotonic()
        process.send_signal(signal.SIGTERM)
        _, err = process.communicate(timeout=5)
        self.assertLess(time.monotonic()-started, 4)
        self.assertEqual(process.returncode, 143)
        self.assertEqual(err, '')
        self.assertEqual(self.status()['signal'], signal.SIGTERM)
        self.assertEqual(self.status()['child_exit_code'], -signal.SIGKILL)
        self.assert_process_stopped(descendant)

    @unittest.skipUnless(os.name == 'posix', 'POSIX signal and process-group behavior')
    def test_normal_exit_cleans_up_remaining_background_process(self):
        pid_path = self.root / 'descendant.pid'
        grandchild = "import os,pathlib,sys,time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)"
        code = ("import pathlib,subprocess,sys,time; "
                f"subprocess.Popen([sys.executable,'-u','-c',{grandchild!r},sys.argv[1]]); "
                "p=pathlib.Path(sys.argv[1])\nwhile not p.exists(): time.sleep(.025)\nprint('parent finished')")
        process = self.launch(code, str(pid_path), fast_shutdown=True)
        out, err = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0)
        self.assertEqual(out, 'parent finished\n')
        self.assertEqual(err, '')
        self.assert_process_stopped(int(pid_path.read_text()))

    def assert_process_stopped(self, pid):
        # Linux may retain a killed orphan as a zombie until init reaps it.
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
            proc_state = Path(f'/proc/{pid}/stat')
            if proc_state.exists() and proc_state.read_text().split(') ', 1)[1].startswith('Z '):
                return
            time.sleep(.025)
        self.fail(f'Background process {pid} is still running')


if __name__ == '__main__':
    unittest.main()
