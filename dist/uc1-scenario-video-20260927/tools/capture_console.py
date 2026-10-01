"""Capture real process stdout, line by line, with monotonic timestamps."""
import argparse
import json
import os
import pathlib
import queue
import signal
import subprocess
import sys
import threading
import time


INTERRUPT_GRACE_SECONDS = 10.0
TERMINATE_GRACE_SECONDS = 5.0
DESCENDANT_GRACE_SECONDS = 2.0


class _LinuxSubreaper:
    """Own orphaned descendants even if MATLAB launches a separate session."""

    def __init__(self):
        self.enabled = False
        self.previous = 0
        if not sys.platform.startswith('linux'):
            return
        import ctypes
        self.libc = ctypes.CDLL(None, use_errno=True)
        previous = ctypes.c_int()
        if self.libc.prctl(37, ctypes.byref(previous), 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), 'Cannot inspect child-subreaper state')
        if self.libc.prctl(36, 1, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), 'Cannot enable child-subreaper cleanup')
        self.previous = previous.value
        self.enabled = True

    @staticmethod
    def _identity(pid):
        try:
            fields = pathlib.Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
            return (pid, int(fields[19]), int(fields[1]), fields[0])
        except (FileNotFoundError, ProcessLookupError):
            return None

    def _children(self, main_pid):
        children = {}
        # /proc children files list only direct children of this process's
        # threads. Detached descendants appear here when Linux adopts them.
        for path in pathlib.Path('/proc/self/task').glob('*/children'):
            try:
                pids = path.read_text().split()
            except FileNotFoundError:
                continue
            for value in pids:
                pid = int(value)
                if pid == main_pid:
                    continue  # Popen exclusively owns/reaps its main child.
                identity = self._identity(pid)
                if identity is not None and identity[2] == os.getpid():
                    children[pid] = identity
        return list(children.values())

    def _signal_owned(self, identity, signum):
        pid, started, parent, _state = identity
        if parent != os.getpid():
            return
        descriptor = None
        try:
            if hasattr(os, 'pidfd_open') and hasattr(signal, 'pidfd_send_signal'):
                descriptor = os.pidfd_open(pid)
            current = self._identity(pid)
            if current is None or current[:3] != (pid, started, os.getpid()):
                return
            if descriptor is not None:
                signal.pidfd_send_signal(descriptor, signum)
            else:
                os.kill(pid, signum)
        except ProcessLookupError:
            pass
        finally:
            if descriptor is not None:
                os.close(descriptor)

    def cleanup(self, main_pid):
        if not self.enabled:
            return True
        deadline = time.monotonic() + DESCENDANT_GRACE_SECONDS
        hard_deadline = deadline + TERMINATE_GRACE_SECONDS
        signalled = set()
        while True:
            children = self._children(main_pid)
            if not children:
                return True
            for identity in children:
                pid, started, _parent, state = identity
                if state == 'Z':
                    try:
                        os.waitpid(pid, os.WNOHANG)
                    except ChildProcessError:
                        pass
                    continue
                signum = signal.SIGKILL if time.monotonic() >= deadline else signal.SIGTERM
                key = (pid, started, signum)
                if key not in signalled:
                    self._signal_owned(identity, signum)
                    signalled.add(key)
            if time.monotonic() >= hard_deadline:
                return not self._children(main_pid)
            time.sleep(.025)

    def restore(self):
        if self.enabled:
            self.libc.prctl(36, self.previous, 0, 0, 0)
            self.enabled = False


def _signal_child(process, signum):
    try:
        if os.name == 'posix':
            os.killpg(process.pid, signum)
        elif process.poll() is None:
            if signum == signal.SIGINT:
                process.send_signal(signal.CTRL_BREAK_EVENT)
            else:
                process.terminate()
    except ProcessLookupError:
        pass


def _group_alive(process):
    if os.name != 'posix':
        return process.poll() is None
    try:
        os.killpg(process.pid, 0)
        return True
    except ProcessLookupError:
        return False


def _pump_output(stream, lines):
    try:
        for line in stream:
            lines.put(line)
    finally:
        lines.put(None)


def capture(command, output):
    """Capture live output; completion metadata is kept outside the transcript.

    POSIX children have their own process group. Linux also adopts orphaned
    listeners launched in detached groups. Forward operator signals, keep
    draining output during shutdown, and bound unresponsive-child cleanup.
    """
    start = time.monotonic()
    status = {'exit_code': 127, 'child_exit_code': None, 'signal': None}
    process = None
    subreaper = None
    pending_signals = []
    previous_handlers = {}
    handled_signals = [signal.SIGINT, signal.SIGTERM]
    if os.name == 'posix':
        # An SSH terminal closing must not orphan the child's separate session.
        handled_signals.append(signal.SIGHUP)
    for signum in handled_signals:
        previous_handlers[signum] = signal.signal(
            signum, lambda received, _frame: pending_signals.append(received))
    try:
        with output.open('x', encoding='utf-8') as events, output.with_suffix('.txt').open('x', encoding='utf-8') as transcript:
            subreaper = _LinuxSubreaper()
            options = {'start_new_session': True} if os.name == 'posix' else {
                'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP}
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, encoding='utf-8', errors='replace', bufsize=1, **options)
            lines = queue.Queue()
            reader = threading.Thread(target=_pump_output, args=(process.stdout, lines), daemon=True)
            reader.start()
            output_closed = False
            stop_phase = 0
            stop_deadline = None
            child_exit_at = None
            descendant_deadline = None
            while True:
                now = time.monotonic()
                while pending_signals:
                    received = pending_signals.pop(0)
                    if status['signal'] is None:
                        status['signal'] = received
                        _signal_child(process, received)
                        stop_phase = 1
                        stop_deadline = now + INTERRUPT_GRACE_SECONDS
                    elif stop_phase < 2:
                        _signal_child(process, signal.SIGTERM)
                        stop_phase = 2
                        stop_deadline = now + TERMINATE_GRACE_SECONDS
                    else:
                        _signal_child(process, getattr(signal, 'SIGKILL', signal.SIGTERM))
                        stop_phase = 3
                        stop_deadline = None
                if stop_deadline is not None and now >= stop_deadline:
                    if stop_phase == 1:
                        _signal_child(process, signal.SIGTERM)
                        stop_phase = 2
                        stop_deadline = now + TERMINATE_GRACE_SECONDS
                    else:
                        _signal_child(process, getattr(signal, 'SIGKILL', signal.SIGTERM))
                        stop_phase = 3
                        stop_deadline = None
                child_code = process.poll()
                if child_code is not None and child_exit_at is None:
                    child_exit_at = now
                    if not subreaper.cleanup(process.pid):
                        raise OSError('Detached child cleanup did not complete within its deadline')
                    # A child may exit before its background listener does.
                    if _group_alive(process):
                        _signal_child(process, signal.SIGTERM)
                        descendant_deadline = now + DESCENDANT_GRACE_SECONDS
                if descendant_deadline is not None:
                    if not _group_alive(process):
                        descendant_deadline = None
                    elif now >= descendant_deadline:
                        _signal_child(process, getattr(signal, 'SIGKILL', signal.SIGTERM))
                        descendant_deadline = None
                try:
                    line = lines.get(timeout=0.1)
                    if line is None:
                        output_closed = True
                    else:
                        events.write(json.dumps({'t': round(time.monotonic()-start, 3), 'text': line.rstrip('\r\n')})+'\n')
                        events.flush()
                        transcript.write(line)
                        transcript.flush()
                        sys.stdout.write(line)
                        sys.stdout.flush()
                except queue.Empty:
                    pass
                if child_code is not None and output_closed and descendant_deadline is None:
                    break
            code = process.wait()
            status['child_exit_code'] = code
            status['exit_code'] = (128 + status['signal']) if status['signal'] is not None else (128 - code if code < 0 else code)
            if code and status['signal'] is None:
                print(f'ACRAM process failed (exit code {status["exit_code"]}).', file=sys.stderr, flush=True)
            return status['exit_code']
    except OSError as exc:
        status['error'] = str(exc)
        if status['signal'] is not None:
            status['exit_code'] = 128 + status['signal']
        print(f'Console capture failed: {exc}', file=sys.stderr, flush=True)
        return status['exit_code']
    finally:
        # Also clean up if writing a log/terminal fails while the child lives.
        if process is not None and _group_alive(process):
            _signal_child(process, signal.SIGTERM)
            try:
                process.wait(timeout=TERMINATE_GRACE_SECONDS)
            except subprocess.TimeoutExpired:
                _signal_child(process, getattr(signal, 'SIGKILL', signal.SIGTERM))
                process.wait()
            if _group_alive(process):
                _signal_child(process, getattr(signal, 'SIGKILL', signal.SIGTERM))
        if process is not None and status['child_exit_code'] is None:
            status['child_exit_code'] = process.poll()
        if subreaper is not None:
            try:
                if process is not None:
                    status['descendant_cleanup_complete'] = subreaper.cleanup(process.pid)
            finally:
                subreaper.restore()
        status['duration_seconds'] = round(time.monotonic()-start, 3)
        try:
            output.with_suffix('.status.json').write_text(json.dumps(status, indent=2)+'\n', encoding='utf-8')
        finally:
            for signum, handler in previous_handlers.items():
                signal.signal(signum, handler)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == '--':
        command = command[1:]
    if not command:
        parser.error('a command is required after --')
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    return capture(command, output)


if __name__ == '__main__':
    sys.exit(main())
