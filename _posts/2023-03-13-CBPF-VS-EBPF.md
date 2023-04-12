---
layout: post
title:  "Stop saying eBPF when you mean cBPF."
date:   2023-03-13 16:00:00 -0400
categories: linux
tags: [linux, ebpf, bpf, cbpf]
---

**TL;DR:** Let's detect malware that uses BPF the right way. eBPF has become a hot
topic, which leads to some hype whenever BPF is found in malware.  The thing is,
BPF malware is nothing new and most malware is using cBPF, not eBPF.  Conflating
cBPF with eBPF is harmful to defenders, who really need to understand the
difference between the two when writing detections.

I'm going to assume you're at least familiar with eBPF at the marketing blog
level. If not, check out
[some](https://ortiz.sh/ebpf/2022/01/04/eBPF-FOR-BEGINNINERS.html)
[of](https://deepfence.io/aya-your-trusty-ebpf-companion/)
[these](https://ortiz.sh/ebpf/2021/11/01/INTRODUCING-OXIDEBPF.html)
[links](https://www.youtube.com/watch?v=Y-ROv4LsO0Q). Or, if those aren't
technical enough, [try](https://tmpout.sh/2/4.html)
[these](https://ortiz.sh/bpf/2021/12/02/THE-HIVE.html).

Also, code examples will come from kernel 6.2.9. This
means the examples can (do, and probably will) change significantly without
warning on newer and older kernels.

# What's the problem?

As you've almost definitely noticed (you did click to read this after all),
interest in eBPF has skyrocketed in the past two or so years. The hype cycle can
make it hard to discern facts from marketing, a critical distinction when trying
to defend against BPF based malware. You've probably heard that eBPF is the
successor to something called cBPF, but unless you've dug deeper than the blog
post level that's probably all you know. As we'll discuss, eBPF and cBPF are
quite different in their operation, capabilities, and defenses.

Let's pick a few recent examples. BlackBerry's writeup of Symbiote intentionally
confuses cBPF with eBPF, explicitly calling what Symbiote attaches with
`setsockopt` "eBPF code.[^1]" You can't actually attach eBPF code with
`setsockopt`. Elastic, in their write up of BPFDoor, does not claim that the
malware uses eBPF, but also does not differentiate the two and does not mention
how the BPF component to the malware is actually loaded. They do link to the
correct cBPF documentation, so it's a bit better [^2]. Sysdig's writeup of
BPFDoor is probably the best, they clearly tell us that eBPF is not involved
right in the title and let defenders know about how `setsockopt` is involved
[^3].

If you look across the internet you'll find a plethora of users and commentators
mixing up the two technologies [^4]. Even the official kernel documentation calls
eBPF a "[significant extension]" of cBPF [^5], which we'll see is a bit of a
fudge.

# What do kprobes have to do with packet filters?

The first clue that this technology has grown far beyond its original scope is
that you can use what is, ostensibly, a _Packet Filter_ to instrument kernel
functions. How did we get here?

The original BPF paper [^8] describes a system for inspecting and filtering
packets from userspace where the filtering is performed in-kernel, reducing the
amount of time that needs to be spent copying every packet into userspace and
netting significant performance gains. As an aside, the paper also calls the
system "BSD Packet Filter," not "Berkeley Packet Filter."  It goes on to
describe an in-kernel "filter machine" which is explicitly not a fully featured
virtual machine that can perform arbitrary filtering. It is specifically focused
on filtering network packets. This technology was adopted in several places in
the kernel, as well as some network device drivers, to filter packets. Then, at
the start of 2012, the onward march of "using packet filters to filter things
that are decidedly not packets" began with SECCOMP filters[^14].

Soon after, in 2014, the `bpf()` syscall was introduced alongside eBPF [^9].
This allowed users to use BPF not just to filter packets, but to filter just
about anything that passes through the kernel (and some stuff that doesn't!).
The official kernel documentation gives a high level overview of some of the new
features [^6]: eBPF increased the amount of registers available from 2 to 10,
increased the register size to 64 bits, and made calling into helper functions
more efficient. Critically, eBPF also changed the encoding of instructions to
support these new features. This means that eBPF bytecode and cBPF bytecode are
_not_ mutually compatible. Is it "significantly extended?" Sure, I suppose, but
there are a lot of fundamental changes that mean cBPF code won't "just work"
with the eBPF specification.

[Here is a cBPF
instruction](https://elixir.bootlin.com/linux/v6.2.9/source/include/uapi/linux/filter.h#L24):

```c
struct sock_filter {    /* Filter block */
        __u16   code;   /* Actual filter code */
        __u8    jt;     /* Jump true */
        __u8    jf;     /* Jump false */
        __u32   k;      /* Generic multiuse field */
};
```

[And here is an eBPF
instruction](https://elixir.bootlin.com/linux/v6.2.9/source/include/uapi/linux/bpf.h#L71):

```c
struct bpf_insn {
	__u8	code;		/* opcode */
	__u8	dst_reg:4;	/* dest register */
	__u8	src_reg:4;	/* source register */
	__s16	off;		/* signed offset */
	__s32	imm;		/* signed immediate constant */
};
```

Interestingly, the instructions _are_ the same size. This was done
intentionally, along with other overlapping features, to make translating or
porting cBPF code into eBPF code easier[^15].  This means that, in theory, you
could shove cBPF bytecode into the `bpf()` syscall.

To prove a point, let's see what happens when we do exactly that. We'll use
`tcpdump`'s ability to output cBPF bytecode to create a dead simple cBPF filter.

```
# tcpdump -i lo -dd
{ 0x6, 0, 0, 0x00040000 },
```

This gives us a code of `0x06`, empty `jt` and `jf`, and a multiuse value of
`0x00040000`. The code of `0x06` corresponds to
[`BPF_RET`](https://elixir.bootlin.com/linux/v6.2.9/source/include/uapi/linux/bpf_common.h#L13),
which indicates that this is a return instruction. The `0x00040000` value
corresponds to the size of the packet (snapshot length) we want to capture. By
default, it's 256 kibibytes. This simple filter immediately returns and says
"grab the whole packet."

```c
#include <linux/bpf.h>
#include <linux/filter.h>
#include <sys/syscall.h>
#include <stdio.h>
#include <unistd.h>

int main() {

    struct sock_filter filter[] = {
        { 0x6, 0, 0, 0x00040000 },
    };

    char * license = "GPL";

    struct bpf_insn* insn = (struct bpf_insn*) &filter;

    union bpf_attr attr = {
        .prog_type = BPF_PROG_TYPE_SOCKET_FILTER,
        .insn_cnt = 1,
        .insns = (unsigned long long) insn,
        .license = (unsigned long long) license,
        // omitted for space
    };


    int ret = syscall(SYS_bpf, BPF_PROG_LOAD, &attr, sizeof(attr));
    if (ret < 0) {
        perror("bpf");
    }

    return 0;
}
```

If we run it we immediately get an `EINVAL`.

```
# cc bpf.c
# ./a.out
bpf: Invalid argument
```

But why does this fail? When the cBPF instruction gets interpreted as an eBPF
instruction, the `0x06` half of the cBPF `code` short ends up in the eBPF `code`
byte. In eBPF this value maps to
[`BPF_JMP32`](https://elixir.bootlin.com/linux/v6.2.9/source/include/uapi/linux/bpf.h#L17).
In eBPF this is called an _instruction class_ and should be paired with an
_operation_ to do something useful. For example, the eBPF equivalent of
`BPF_RET` is
[`BPF_EXIT_INSN`](https://elixir.bootlin.com/linux/v6.2.9/source/include/linux/filter.h#L387)
which is the OR of `BPF_JMP` (class) and `BPF_EXIT` (operation). When we pass
this filter straight into the `bpf` syscall we end up in the
[`check_subprogs`](https://elixir.bootlin.com/linux/v6.2.9/source/kernel/bpf/verifier.c#L2402)
function, which checks our code and falls through to the subprogram length
check. Because we fell through, the verify knows we must have some kind of jump
instruction. Because our program is only one instruction long, the jump is
necessarily out of range, and the verification fails.

```c
off = i + insn[i].off + 1; // off = 1 for the cBPF program, subprog_end = 1
if (off < subprog_start || off >= subprog_end) {
	verbose(env, "jump out of range from insn %d to %d\n", i, off);
	return -EINVAL;
}
```

Of course you might be able to hand craft a valid cBPF-eBPF polyglot, but the
point remains that the two are neither designed nor intended to be mutually
compatible. The correct way to load a cBPF filter into eBPF is to simply load
the filter as usual, with `SO_ATTACH_FILTER` set while calling `setsockopt`.  In
a modern kernel this will get verified by `bpf_check_classic` and, assuming it
passes, translated into eBPF bytecode by `bpf_convert_filter` before being
attached and ran.

When thinking about the difference between cBPF and eBPF, it's better to think
of it as more of a Python 2 to Python 3 style conversion and not as a C to C++
style conversion[^pedantic]. eBPF is its own new thing, not a superset of cBPF.

[^pedantic]: I suppose C++ is not strictly a superset of C, due to differences
in behaviors in the specs. But it's close enough for this metaphor.

# BPF as Malware

Let's get back to malware. How is BPF actually being used in malware today?  As
it turns out, it's mostly cBPF filters. It makes a lot of sense that malware
authors would avoid eBPF. The capabilities are evolving rapidly, changes to the
verifier and differences in patch sets mean you can't be sure your filters will
always work, and the lack of widespread BTF adoption until recently makes
running filters across different kernels tricky. If you want to target the
broadest base of Linux systems, you have to stick to cBPF.

Let's take a look at a list of malware that leverages BPF, borrowed from
a Hushcon talk [^7].

* cd00r (or cDoor): uses libpcap to build a cBPF filter
* Turla's Penquin: similar to cd00r, uses a cBPF filter for persistence
* CIA's HIVE: uses a cBPF socket filter similar to cd00r
* NSA's dewdrop: again, uses a flexible cBPF socket filter

What's the common theme here? Some kind of backdoor persistence, activated with
a cBPF filter. What about something more modern?

Let's look at Symbiote first, from one of the samples that actually leverages
BPF.

```c
0000d62c      memcpy(rax_10, &filter, 0x1d0)
0000d65c      memcpy(rax_10 + 0x1d0, *(arg4 + 8), zx.q(*arg4) << 3)
0000d664      int16_t var_38 = var_58.w
0000d66c      uint64_t var_30 = rax_10
0000d69f      return syscall(0x36, zx.q(arg1), zx.q(arg2), zx.q(arg3), &var_38, zx.q(arg5))
```

That syscall number, `0x36`, is `setsockopt`. This is a cBPF filter.

Alright, what about BPFdoor? The source code for that allegedly got leaked, and
we can see that it indeed uses cBPF[^16].  This sources matches what can be seen
from captured samples, so it should be pretty safe to say eBPF is not used here.

But certainly someone is using eBPF maliciously, right? Probably! But if it
exists, we aren't looking in the right places for it. There are a number of
academic projects demonstrating the capabilities of eBPF for malware, and they
are impressive. TripleCross [^10] is a comprehensive rootkit built on eBPF, as
are ebpfkit [^11] and boopkit [^12]. But again, either eBPF is being avoided by
malware authors in the wild, or we simply aren't looking hard enough.

# Filtering the Filter

Okay, great, so we know that eBPF and cBPF are different and that malware tends
to prefer cBPF. How do we actually defend against it? Even without in the wild
samples the capabilities of eBPF malware have been clearly demonstrated and we
probably want to protect ourselves from both.

## Classical Detections

There are a few ways to attach cBPF filters. We can see them by checking for
places in the kernel where `struct sock_fprog` is used[^17].  We find five
methods, one of which is most common.

The first, which is what malware mostly uses, is to call `setsockopt` with the
`SO_ATTACH_FILTER` option. This does exactly what it sounds like, you tell the
kernel you want to attach a filter to a socket. Similarly, you can call
`setsockopt` on a `packet` socket with `PACKET_FANOUT_DATA` to attach a filter
to a fanout socket.  The type determines what kind of BPF filter gets attached,
either `PACKET_FANOUT_CBPF` for cBPF or `PACKET_FANOUT_EBPF` for eBPF. Note that
this does not bypass the `bpf()` syscall for eBPF, as you may not pass in an
eBPF program directly. Instead, you must pass in an eBPF program file descriptor
returned by the `bpf()` syscall. For cBPF, on the other hand, you may pass in
the filter program directly.

The next way is to call `prctl` with the `PR_SET_SECCOMP` option and the first
argument set to `SECCOMP_MODE_FILTER`. Like `setsockopt`, this will take an
array of `sock_filter` structs (i.e., a cBPF program). The fourth and fifth ways
are both `ioctl` calls on `tun` and `ppp` devices. The `TUNATTACHFILTER` `ioctl`
attaches a cBPF filter to a `tun` device. The `PPPIOCSPASS`, `PPPIOCSACTIVE`,
`PPPCIOSPASS32`, and `PPPCIOSACTIVE32` `ioctl`s all attach cBPF filters to `ppp`
devices.

By monitoring these three calls for these five patterns, we can observe whenever
a cBPF program is loaded. We can also simplify pattern matching on `setsockopt`,
`prctl`, and `ioctl` syscalls by observing the `bpf_prog_create_from_user`
kernel function, `sk_attach_filter` kernel function, and `get_filter` kernel
function.  The `bpf_prog_create_from_user` function is used by the packet fanout
filter and SECCOMP filters. The `sk_attach_filter` function is used by the
standard socket filter and `tun` driver. And finally, `get_filter` is used by
the `ppp` driver.

Note that is it possible to attach a socket filter using the `bpf` syscall, with
`BPF_PROG_TYPE_SOCKET_FILTER`. However, the supplied bytecode here must be eBPF
bytecode (remember, eBPF is not a superset of cBPF) so this is really just a
special case of loading an eBPF program.

## Extended Detections

Detecting eBPF is significantly easier. No matter what else you want to do with
it, you'll need to load your program with the `bpf` syscall. After that, there's
a ton of stuff that can be done to attach to filter to so, so many different
things.  But that `bpf` call must always be there. If we want to detect eBPF,
we only have to monitor this one point in the kernel.

# Can you summarize that for me?

Sure. BPF is an umbrella term for both cBPF and eBPF, which are very different.
If you're concerned about BPF in malware you most likely want to be watching
`sk_attach_filter`, which is cBPF. If you're concerned about eBPF in malware you
only need to worry about the `bpf` syscall.

# References

[^1]: [https://blogs.blackberry.com/en/2022/06/symbiote-a-new-nearly-impossible-to-detect-linux-threat](https://blogs.blackberry.com/en/2022/06/symbiote-a-new-nearly-impossible-to-detect-linux-threat)
[^2]: [https://www.elastic.co/security-labs/a-peek-behind-the-bpfdoor](https://www.elastic.co/security-labs/a-peek-behind-the-bpfdoor)
[^3]: [https://sysdig.com/blog/bpfdoor-falco-detection/](https://sysdig.com/blog/bpfdoor-falco-detection/)
[^4]: [https://news.ycombinator.com/item?id=33489935](https://news.ycombinator.com/item?id=33489935)
[^5]: [https://www.kernel.org/doc/html/v6.0/bpf/bpf_licensing.html#background](https://www.kernel.org/doc/html/v6.0/bpf/bpf_licensing.html#background)
[^6]: [https://www.kernel.org/doc/html/v6.0/bpf/classic_vs_extended.html](https://www.kernel.org/doc/html/v6.0/bpf/classic_vs_extended.html)
[^7]: Evolution of Stealth Packet Filters, Hushcon Seattle 2022, Richard Johnson (@richinseattle) at Fuzzing IO / Trellix
[^8]: Steven McCanne and Van Jacobson. 1993. The BSD packet filter: a new architecture for user-level packet capture. In Proceedings of the USENIX Winter 1993 Conference Proceedings on USENIX Winter 1993 Conference Proceedings (USENIX'93). USENIX Association, Berkeley, CA, USA, 2-2. [http://www.tcpdump.org/papers/bpf-usenix93.pdf]
[^9]: [https://man7.org/linux/man-pages/man2/bpf.2.html](https://man7.org/linux/man-pages/man2/bpf.2.html)
[^10]: [https://github.com/h3xduck/TripleCross](https://github.com/h3xduck/TripleCross)
[^11]: [https://github.com/Gui774ume/ebpfkit](https://github.com/Gui774ume/ebpfkit)
[^12]: [https://github.com/krisnova/boopkit](https://github.com/krisnova/boopkit)
[^13]: [https://man7.org/linux/man-pages/man2/bpf.2.html](https://man7.org/linux/man-pages/man2/bpf.2.html)
[^14]: [https://lwn.net/Articles/475043/](https://lwn.net/Articles/475043/)
[^15]: [https://www.kernel.org/doc/html/v6.0/bpf/classic_vs_extended.html#opcode-encoding](https://www.kernel.org/doc/html/v6.0/bpf/classic_vs_extended.html#opcode-encoding)
[^16]: [https://github.com/snapattack/bpfdoor-scanner/blob/main/sample/bpfdoor.c#L462](https://github.com/snapattack/bpfdoor-scanner/blob/main/sample/bpfdoor.c#L462)
[^17]: [https://elixir.bootlin.com/linux/latest/C/ident/sock_fprog](https://elixir.bootlin.com/linux/latest/C/ident/sock_fprog)
