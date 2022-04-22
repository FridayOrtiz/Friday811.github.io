---
layout: post
title: "eBPF for security: a beginner's guide"
date:   2022-01-04 00:00:00 -0500
categories: ebpf
---

**This post was written for Red Canary and originally appeared on their site
[here](https://redcanary.com/blog/ebpf-for-security/).**

Red Canary has started to incorporate
[eBPF](https://en.wikipedia.org/wiki/Berkeley_Packet_Filter) into our Linux
sensor. We wanted to explain, at a high level, what eBPF is and how it helps us
protect our customers. We’ll start by describing the shortcomings we’ve
experienced in gathering security telemetry and then explain how eBPF helps us
solve these shortcomings. We’ll close by reviewing some of the challenges we
faced in building eBPF support into our
[MDR](https://redcanary.com/products/managed-detection-and-response/) product,
and how we overcame them.  We expect to offer Red Canary customers full eBPF
telemetry support in the coming months, which will be announced in upcoming
release notes.

## What's the problem?

In order to detect suspicious or malicious events, we need to gather a lot of
telemetry from a running system. We use this telemetry to understand what
system calls are happening, what processes are running, and how the system is
behaving. Some examples of telemetry we gather are process start events,
network connections, and namespace changes. There are [many
ways](https://redcanary.com/blog/linux-security-testing/) we can gather this
information on a [Linux system](https://redcanary.com/blog/linux-101/), but
they are not all created equal. For example, we can gather information on
processes opening files by regularly scanning `procfs` for open file
descriptors.  However, depending on our intervals, we might miss files that are
opened and closed quickly. Or we could note down the file descriptor, only to
have it point at a different file by the time we read it.

The ideal place to gather information on these events is directly inside the
kernel. Traditionally, this can be done with the [Linux Auditing
subsystem](https://wiki.archlinux.org/title/Audit_framework) or with a [Linux
kernel module
(LKM)](https://sysprog21.github.io/lkmpg/#what-is-a-kernel-module). An
alternative that’s quickly gaining traction is to gather this telemetry with
eBPF, which excels at high-performance kernel instrumentation and improved
observability.

## What is eBPF and why is it useful?

[Berkeley Packet Filter](https://ebpf.io/) is a Linux kernel subsystem that
allows a user to run a limited set of instructions on a virtual machine running
in the kernel. It is divided between classic BPF (cBPF) and extended BPF (eBPF,
or simply BPF). The older cBPF was limited to observing packet information,
while the newer eBPF is much more powerful, allowing a user to do things such
as modify packets, change syscall arguments, modify userspace applications, and
more.

### Safer than kernel modules

Why is this useful? Because normally if we want to run arbitrary code in the
kernel, we would need to load in a kernel module. Putting aside the security
implications for a moment, running code in the kernel is dangerous and error
prone. If you make a mistake in a normal application, it crashes. If you make a
mistake in kernel code, the computer crashes. Security is about managing
business risk, so a security tool isn’t very useful if it brings down
production. BPF offers us a safe alternative, while providing nearly the same
amount of power. You can run arbitrary code in a kernel sandbox and collect
information without the risk of breaking the host.

You can also think of BPF as a web application, whereas a kernel module is a
standalone application. Which one do you trust more: visiting a website or
downloading and running an application? Visiting a website is safer; a web
application runs in a sandbox and can’t easily do as much damage to your
machine as a downloaded application.

### More efficient than AuditD

[This
post](https://capsule8.com/blog/auditd-what-is-the-linux-auditing-system/)
gives an excellent overview of [AuditD](https://linux.die.net/man/8/auditd)’s
strengths and weaknesses, but let’s compare it directly against BPF.

AuditD is relatively slow when it comes to collecting information, and incurs a
non-negligible performance penalty on the system under audit. BPF offers us a
significant performance advantage: we can perform some filtering, collection,
and analysis within the kernel. Moving information from inside the kernel to
outside the kernel is a relatively slow process (details of which are outside
the scope of this post). The more work, collection, and analysis we can do
inside the kernel, the faster our system will run.

AuditD is also relatively inflexible, whereas BPF gives us great flexibility.
AuditD telemetry is limited to the events that the tool is designed to
generate, and what we can configure it to tell us about. With BPF, we can
instrument and inspect any point in the kernel we want to. We can look at
specific code paths, examine function arguments, and generally collect as much
information as we need to inform decision making.

BPF also allows many simultaneous consumers, allowing us to happily live
alongside any other programs that take advantage of BPF. By contrast, AuditD
can only be used by one program at a time. Once events are consumed from
AuditD, they’re gone.

## How do I collect telemetry from eBPF?

In order to get security telemetry from BPF, we need two main components:

1. the BPF programs themselves, to gather information from the kernel and
   expose it in a useful format
2. a way to load and interact with these BPF programs

Red Canary’s Research & Development team has built and released both of these
components as free open source software. With these components in place, anyone
can start to move away from relying on AuditD and Linux kernel modules to
gather security telemetry.

### Red Canary’s eBPF sensor

The
[redcanary-ebpf-sensor](https://github.com/redcanaryco/redcanary-ebpf-sensor)
is the set of BPF programs that actually gather security relevant event data
from the Linux kernel. The BPF programs are combined into a single ELF file
from which we can selectively load individual probes, depending on the
operating system and kernel version we’re running on.  The probes insert
themselves at various points in the kernel (such as the entrypoint and return
of the `execve` system call) and gather information on the call and its
context.  This information is then turned into a telemetry event, which is sent
to userspace through a `perf` buffer.

By having multiple probes in the same ELF binary, we can take advantage of
newer kernel features (such as the `read_str` family of BPF functions), or probe
newer syscalls (such as `clone3`) while retaining backwards compatibility with
older kernels. This lets us build a Compile-Once, Run-Most-Places BPF sensor
package.

### oxidebpf

[`oxidebpf`](https://github.com/redcanaryco/oxidebpf) is a Rust library that
manages eBPF programs. The goal of `oxidebpf` is to provide a simple interface
for managing multiple BPF program versions in a Compile-Once, Run-Most-Places
way. For example, here’s how easy it is to build a probe that attaches to
`clone3` and `clone`, but only if `clone3` exists on the target system.

```rust
let mut program_group = ProgramGroup::new(None);

program_group.load(
    program_blueprint,
    vec![ProgramVersion::new(vec![
        Program::new(
            "test_program_clone",
            &["sys_clone"],
        )
        .syscall(true),
        Program::new(
            "test_program_clone3",
            &["sys_clone3"],
        )
        .optional(true)
        .syscall(true),
    ])]
)?;
```

Read our [blog post](https://redcanary.com/blog/oxidebpf/) for a more detailed
overview of `oxidebpf`, along with a tutorial.

**Author's Note: That blog post is also cross posted here:
[https://ortiz.sh/ebpf/2021/11/01/INTRODUCING-OXIDEBPF.html](https://ortiz.sh/ebpf/2021/11/01/INTRODUCING-OXIDEBPF.html).
The tutorial is not updated for oxidebpf versions >= 0.2.**

### Coming soon: a GPS for the Linux kernel

One last thing we need to achieve Run-Most-Places is kernel offsets. To get
some of the information we want out of the kernel, we need to pull that
information out of kernel data structures. Unfortunately, these structures are
not guaranteed to form a stable application binary interface (ABI) and can vary
across kernel versions and distributions. The typical way to solve this is to
build your BPF program on the host you’re targeting and grab information
addresses locally. Unfortunately, that’s not great for ephemeral systems,
short-lived systems, or systems that can’t spare the resources to build and
rebuild sensors. Alternatively, newer kernels support BPF features that take
care of this for the developer, facilitating true Compile-Once, Run-Everywhere
(CO-RE). Unfortunately, for a variety of legitimate reasons, customers aren’t
always running newer kernels.

To tackle this problem, we’re building a system called the Linux Kernel
Component Cloud Builder (LKCCB). LKCCB is an automated system that determines
structure offsets for every kernel version and distribution we want to run our
BPF probes on. These kernel offsets will then be dynamically loaded into the
probes at runtime (using `oxidebpf`’s BPF hashmap interface). The probes will
be able to check the loaded offsets and use them to navigate through kernel
data structures appropriate for their host environment, returning exactly the
information we’re looking for.

Think of it as a GPS for the Linux kernel. Our probes will be able to rely on
it to find their way, without needing to memorize the lay of the land (i.e.,
compile on the host). Look out for its open source release in 2022!

## What kind of results should I expect?

### More system throughput

We benchmarked our eBPF probes in `redcanary-ebpf-sensor` against `auditd` by
loading them with `oxidebpf` and comparing execl per second throughput using
`byte-unixbench`. The system tested on was a set of four core virtual machines
with 2GB of RAM each, running on a 3950X with 64GB of RAM. The baseline VM had
a throughput of `19421.4 execl/s`. With `auditd` set to trace `execve` and
`execveat` events, we measured a throughput of `14187.4 execl/s`. The
equivalent set of eBPF probes from our sensor ran with a throughput of `16273.1
execl/s`. That’s an approximate 15 percent increase in total system throughput,
just for exec tracing. If we include the full `auditd` configuration required for
our Linux sensor, the system throughput drops to `11989 execl/s`. The equivalent
set of eBPF probes from our sensor gets us a throughput of `14254 execl/s`, an
approximate 19 percent increase in throughput.

### Collect information directly from the kernel

On some Linux kernel versions, we’ve experienced AuditD reporting incorrect
inode numbers for containerized (i.e., `namespaced`) processes. AuditD
notoriously struggles with containers, likely due to the subsystem predating
the popularization of container technology. This requires a userspace
workaround in which we query `procfs` for the information we miss. When AuditD
is auditing process forks (i.e., `clone`, `clone3`, `fork`, `vfork`) it returns
the child PID as-is from the system call’s return codes. The PID returned is in
the PID namespace of the child, and not the root PID namespace. This makes it
very difficult to use AuditD to keep track of process lineage in containerized
environments. With eBPF, however, we can instrument a point in the kernel
that’s on the return path from a process fork to the child process, and inspect
the child process’s current `task_struct` to get the true root namespace PID.

By switching to BPF, we can collect inode information directly from the kernel.
If there are kernel version-specific bugs, we can mitigate them by modifying or
creating a new probe. The checks can happen in kernel space, avoiding the
relatively slow and expensive check against procfs, as well as the inherent
race conditions stemming from gathering data in multiple locations
asynchronously.

## How do I get started?

You can find all of our eBPF for security tools on GitHub:

*  [redcanary-ebpf-sensor](https://github.com/redcanaryco/redcanary-ebpf-sensor)
*  [oxidebpf](https://github.com/redcanaryco/oxidebpf)

As always, we welcome and encourage you to contribute!
