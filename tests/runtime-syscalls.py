"""Exercise the generated Linux amd64 program under controlled write results.

Only the child launched by this test is traced. No compiler dependency on
Python, libc, or ptrace is introduced. The parent harness enforces a timeout.
"""
import ctypes
import os
import signal
import sys

FIELDS = ("r15 r14 r13 r12 rbp rbx r11 r10 r9 r8 rax rcx rdx rsi rdi "
          "orig_rax rip cs eflags rsp ss fs_base gs_base ds es fs gs").split()


class Registers(ctypes.Structure):
    _fields_ = [(name, ctypes.c_ulonglong) for name in FIELDS]


libc = ctypes.CDLL(None, use_errno=True)
libc.ptrace.restype = ctypes.c_long
libc.ptrace.argtypes = [ctypes.c_uint, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p]


def trace(request, pid, data=None):
    result = libc.ptrace(request, pid, None, data)
    if result == -1:
        raise OSError(ctypes.get_errno(), "ptrace failed")
    return result


def main():
    artifact, mode = sys.argv[1:]
    if mode not in ("partial-eintr", "zero", "error"):
        raise ValueError("Unknown injection mode")
    pid = os.fork()
    if pid == 0:
        try:
            trace(0, 0)  # TRACEME; exec supplies the initial stop.
            os.execve(artifact, [artifact], {})
        finally:
            os._exit(125)
    reaped = False
    try:
        _, status = os.waitpid(pid, 0)
        if not os.WIFSTOPPED(status):
            raise RuntimeError("Tracee did not reach exec stop")
        trace(0x4200, pid, 1 | (1 << 20))  # TRACESYSGOOD | EXITKILL
        entering, writes, pending = True, 0, None
        while True:
            trace(24, pid)  # SYSCALL
            _, status = os.waitpid(pid, 0)
            if os.WIFEXITED(status):
                reaped = True
                code = os.WEXITSTATUS(status)
                expected_calls = 5 if mode == "partial-eintr" else 1
                if writes != expected_calls:
                    raise RuntimeError(f"Expected {expected_calls} writes, got {writes}")
                if (code == 0) != (mode == "partial-eintr"):
                    raise RuntimeError(f"Unexpected artifact exit {code}")
                return code
            if os.WIFSIGNALED(status):
                reaped = True
                raise RuntimeError("Tracee terminated by signal")
            if os.WSTOPSIG(status) != signal.SIGTRAP | 0x80:
                raise RuntimeError("Unexpected trace stop")
            regs = Registers()
            trace(12, pid, ctypes.byref(regs))  # GETREGS
            if entering and regs.orig_rax == 1:
                writes += 1
                original_count = regs.rdx
                injected = None
                if mode != "partial-eintr":
                    injected = 0 if mode == "zero" else -5
                elif writes in (1, 3):
                    injected = -4  # EINTR before and after a written prefix.
                else:
                    regs.rdx = min(original_count, 1 if writes == 2 else 2) if writes < 5 else original_count
                if injected is not None:
                    regs.orig_rax = (1 << 64) - 1  # Skip this kernel write.
                pending = original_count, injected
                trace(13, pid, ctypes.byref(regs))
            elif not entering and pending is not None:
                original_count, injected = pending
                regs.rdx = original_count
                if injected is not None:
                    regs.rax = injected % (1 << 64)
                trace(13, pid, ctypes.byref(regs))
                pending = None
            entering = not entering
    finally:
        if not reaped:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)


if __name__ == "__main__":
    sys.exit(main())
