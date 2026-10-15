# Throwaway: runs a command in a real pty, sends Ctrl+C (byte 0x03) after N seconds, saves raw terminal bytes.
# Usage: python3 -I run-pty.py <seconds> <out-file> <cmd...>
import os, pty, select, sys, time
secs, out, cmd = float(sys.argv[1]), sys.argv[2], sys.argv[3:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
buf, sent, end = b'', False, time.time() + secs
while True:
    if not sent and time.time() >= end:
        os.write(fd, b'\x03'); sent = True
    r, _, _ = select.select([fd], [], [], 0.05)
    if r:
        try: d = os.read(fd, 65536)
        except OSError: break
        if not d: break
        buf += d
open(out, 'wb').write(buf)
_, status = os.waitpid(pid, 0)
print('exit status', status, 'signaled' if os.WIFSIGNALED(status) else 'exited', os.WSTOPSIG(status) if os.WIFSTOPPED(status) else (os.WTERMSIG(status) if os.WIFSIGNALED(status) else os.WEXITSTATUS(status)))
