---
layout: post
title: ""
date: 2024-09-16 15:00:00 -0400
categories: linux
tags: [linux, ebpf]
---

**TL;DR**: Signed division is hard and sometimes it makes the kernel sad.


I was perusing the BPF mailing list, as one does, and this particular bug stood
out.


[[PATCH bpf-next 1/2] bpf: Fix a sdiv overflow issue](https://lore.kernel.org/bpf/20240911044017.2261738-1-yonghong.song@linux.dev/T/)


This problem is not unique to eBPF. It occurs when you perform a signed division
where the result doesn't fit in the destination register. The easiest example is
to take the largest possible negative number that can fit in a register and
divide it by -1. The result should be a positive number, but it overflows into
the sign bit, and the result is invalid. In the multiplication case, such an
overflow is indicated through carry and overflow flags, and the result gets
stored in two registers anyway. Implementing this isn't as clean for division,
and may not have been feasible on early 8086 ALUs (they just didn't have enough
internal registers), so for historical reasons x86 will throw a CPU #DE
exception when a signed division overflows in this manner.

If you want to know more about how this works, Ken Shirriff's blog has a great
article reverse engineering the microcode implementation of
[division](https://www.righto.com/2023/04/reverse-engineering-8086-divide-microcode.html)
and
[multiplication](https://www.righto.com/2023/03/8086-multiplication-microcode.html)
on the original 8086.

It's worth noting that there are other ways to trigger the #DE exception outside
the simple `LLONG_MIN/-1` case. Any division where the result is too large for
the destination register will do. Unfortunately, the BPF JIT forces signed
division to happen with [all 64 bit
registers](https://elixir.bootlin.com/linux/v6.11.6/source/arch/x86/net/bpf_jit_comp.c#L1668).
Or at least, I haven't found a way to force it to use different sized registers.

## Why does this crash the kernel?

It doesn't just crash in the kernel, it crashes in userspace too! The mailing list
has an example.

```
#include <limits.h>
#include <stdio.h>

void main() {
    long long a = LLONG_MIN;
    long long b = -1;
    printf("a/b: %lld\n", a / b);
}
```

If we try to run this, we get the following.

```
$ cc example.c
$ ./a.out
[1]    254041 floating point exception (core dumped)  ./a.out
```

In the userspace case, the kernel catches the hardware exception and signals the
program to handle it. This program doesn't handle it, so it crashes. When this
happens in the kernel, we get an oops (not necessarily a panic), and the kernel
attempts to kill the offending process and recover. If this happens enough, or
without a corresponding userspace program, or is otherwise not recoverable, the
kernel crashes.

## Building Clang

Replicating this bug isn't super easy, but it's not super hard either. Signed
division instructions require targeting the eBPF ISA version 4. By default,
clang only targets v1, and the default clang in my distro only supports targets
up to v3.

Signed division instructions are not supported in all kernel versions either,
they were added to the kernel in 6.6 as part of the effort to support the v4
spec. [LLVM support for SDIV came in 18.0](https://github.com/llvm/llvm-project/commit/6c412b6c6faa2dabd8602d35d3f5e796fb1daf80).[^ebpf]

So the first step is to build clang with support for v4 target, then use that to
build the crash.

## The Crash

The crash itself is simple. The following assembly will trigger it. If you stick
this in any kprobe, it will cause a #DE whenever the probe is hit. This is left
as an exercise to the reader.

```c
#include <limits.h>

// ... inside kprobe
long long min = LLONG_MIN;
asm volatile("r1 = %[m];\t\n"
             "r1 s/= -1;\t\n"
             : [m] "=r"(min)
             : "r"(min)
             : "r1");
```

The fix, in the patch, is to have the verifier look for signed divisions and
patch the actual eBPF assembly to catch and avoid this at runtime. You did know
the verifier patches your programs before loading them, right? It's part of the
sandboxing of eBPF programs. In theory, a good compiler will generate assembly
that does something similar to avoid the runtime problem. But, since it's
possible to submit handwritten assembly to be loaded, the verifier just goes
ahead and live patches certain instructions so they don't cause issues. The
patch doesn't cause the probe to exit or otherwise error, it just makes the
result of the division `LLONG_MIN`, as though the SDIV never happened.

As of writing the fix is in bpf-next, but my local kernel still crashes.


## Exploitability

Is it exploitable? Maybe. Whatever process causes the exception gets killed.  If
you can find a place in the kernel to trigger this exception where you expect a
specific program to be `current`, you can block that program from executing.
The consequences of this will be system specific. Unprivileged users shouldn't
be able to load eBPF though, and there are probably better ways to bring a
system down if you do have privileges. Maybe if you only have the ability to
load eBPF, and you really want something to crash.

There's also a possibility of exploiting an eBPF program that may be tricked
into performing this operation. For example, it might be possible to send a
malicious packet that causes this exception to be triggered in an XDP program,
crashing a firewall service. (N.B., I do not know how a #DE would be handled by
the kernel in the XDP case where there is no `current` task, I assume it would
crash.) I doubt this is any kind of problem in practice, since I expect most
production eBPF programs are targeting the v1 ISA spec and anyone bleeding edge
enough to be relying on signed divisions is probably aware they need to mitigate
this issue, or patch their kernel, or both.

On that note, please let me know if you know of any eBPF programs that can be
exploited while loaded to any ends. I'm sure they exist and I'm trying to learn
more about them. I created a [vulnerable eBPF
program](/linux/2024/09/05/VULNBPF-CHAL-01.html) as an example of what might be
possible if you exploit the loaded eBPF itself.

## References

[^ebpf]: https://pchaigno.github.io/bpf/2021/10/20/ebpf-instruction-sets.html