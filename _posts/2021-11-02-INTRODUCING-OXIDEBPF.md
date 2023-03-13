---
layout: post
title: "Introducing oxidebpf: an open source Linux tool for Rust and eBPF developers"
date:   2021-11-01 00:00:00 -0500
categories: ebpf
tags: [ebpf, linux, rust, c]
---

**This post was written for Red Canary and originally appeared on their site
[here](https://redcanary.com/blog/oxidebpf/).**

**Author's Note: This was originally written for an old version of `oxidebpf`
(0.1.0, the initial release).**

BPF is a [Linux kernel](https://redcanary.com/blog/linux-101/) subsystem that
allows a user to run a limited set of instructions on a virtual machine running
in the kernel. It is divided between classic BPF (cBPF) and extended BPF (eBPF,
or simply BPF). The older cBPF was limited to observing packet information,
while the newer eBPF is much more powerful, allowing a user to do things such
as modify packets, change syscall arguments, modify userspace applications, and
more.

## Why did we create `oxidebpf`?

We wanted to create a fully BSD-3 licensed library to allow users maximum
flexibility in how they manage BPF programs. There are already a number of
fantastic libraries for interfacing with eBPF. However, none of them met our
exact use case, and licensing was a major hurdle.

eBPF has a wide range of capabilities that can be leveraged for security
applications, but it has evolved significantly over a range of major kernel
versions. This has made it difficult to release commercial products wherein a
customer isn’t responsible for building and deploying the eBPF component
themselves. Customers don’t want to do that, nor do they want to be on the
bleeding edge of the Linux kernel (perhaps they rely on a driver that hasn’t
been updated yet, or they simply use whatever kernel their distro of choice
provides and don’t actively think about it).

One of the major features we implemented in oxidebpf is the ability to compose
arbitrary eBPF programs independently from the file they’re compiled in. This
leaves behind the all-or-nothing approach of many other libraries and allows
the consuming application more flexibility to define what an eBPF program
actually is: a series of functions and maps, independent of the container
format they are stored in.

We want oxidebpf to be as easy as possible for the end user. You import the
library, give it a built eBPF program, tell it what you want to load and how,
and you’re done.

## How do I get started?

**Author's note: This should work on 0.1, but the interface is somewhat
different from 0.2 onwards. See the talk linked at the beginning of this
post.**

oxidebpf assumes you already have a compiled eBPF program ready to load. We
have a minimal example of a eBPF program included under
[test/test_program.c](https://github.com/redcanaryco/oxidebpf/blob/main/test/test_program.c).
We’ve also included a
[Makefile](https://github.com/redcanaryco/oxidebpf/blob/main/test/Makefile),
[Dockerfile](https://github.com/redcanaryco/oxidebpf/blob/main/test/Dockerfile),
and
[YAML](https://github.com/redcanaryco/oxidebpf/blob/main/test/docker-compose.yml)
file for easily setting up an environment to build eBPF programs.

Please note that this example is marked with a `Proprietary` license, which means
it can’t do anything useful. All the helper functions and exported symbols
you’ll want to use to do meaningful work are exported as GPL-only. You’ll want
to use something GPL-compatible in practice. Our approach has been to release a
generic BPF sensor program under GPL-2.0 that our customers can selectively
load into our proprietary software. Because oxidebpf is BSD-3-licensed, it
gives you the freedom to adopt this approach and develop a fully GPL-compatible
licensed tool (or use any other licensing you choose, so long as the BPF
licensing is respected).

We will assume your project has the following structure, where the contents of
the `bpf/` directory are copied from the `test/` directory of oxidebpf:

```
.
├── Cargo.toml
├── bpf
│ ├── Dockerfile
│ ├── Makefile
│ ├── docker-compose.yml
│ └── test_program.c
└── src
└── main.rs
```

Let’s say we want to trace the process identifier (PID) of any process that
receives a TCP message from `tcp_recvmsg`. We’ll want to make some modifications
to `test_program.c`.

First, we’ll remove all the unnecessary maps and probes and add prototypes for
the functions and structure we actually use.

```c
#include <linux/kconfig.h>
#include <linux/bpf.h>

static unsigned long long (*bpf_get_current_pid_tgid)(void) =
    (void *)14;
static unsigned long long (*bpf_get_current_uid_gid)(void) =
    (void *)15;
static int (*bpf_perf_event_output)(void *ctx, void *map, int index, void *data, int size) =
    (void *)25;
static unsigned long long (*bpf_get_smp_processor_id)(void) =
    (void *)8;

struct bpf_map_def {
    unsigned int type;
    unsigned int key_size;
    unsigned int value_size;
    unsigned int max_entries;
    unsigned int map_flags;
};
```

Then, we’ll add a new `BPF_MAP_TYPE_PERF_EVENT_ARRAY` for communicating PIDs
back to our program.

```c
struct bpf_map_def __attribute__((section("maps/pid_events"), used)) pid_events = {
    .type = BPF_MAP_TYPE_PERF_EVENT_ARRAY,
    .key_size = sizeof(u32),
    .value_size = sizeof(u32),
    .max_entries = 1024,
    .map_flags = 0,
};
```

Then we’ll want to create a struct for passing the PID back to our program
through the `perf` map.

```c
typedef struct {
    u32 pid;
    u32 tgid;
    u32 uid;
    u32 gid;
} pid_tgid_msg;
```

Now we can add a new program that will get the current PID and send it through
the `perf` map.

```c
__attribute__((section("kprobe/trace_pid_event"), used)) int test_program(struct pt_regs *regs)
{

    u32 pid = bpf_get_current_pid_tgid();
    u32 tgid = bpf_get_current_pid_tgid() >> 32;
    u32 uid = bpf_get_current_uid_gid();
    u32 gid = bpf_get_current_uid_gid() >> 32;
    pid_tgid_msg msg = {
        .pid = pid,
        .tgid = tgid,
        .uid = uid,
        .gid = gid,
    };
    bpf_perf_event_output(regs, &pid_events, bpf_get_smp_processor_id(),
            &msg, sizeof(msg));
    return 0;
}
```

Finally, we change the license of the program to `GPL` so we can do useful work
(the verifier will reject calling `bpf_perf_event_open()` from a proprietary
program).

```c
char _license[] __attribute__((section("license"), used)) = "GPL";
```

We can build this with `docker compose run --rm test-builder`, giving us a
`test_program_x86_64`.

Our project directory now looks like this:

```
.
├── Cargo.toml
├── bpf
│ ├── Dockerfile
│ ├── Makefile
│ ├── docker-compose.yml
│ ├── test_program.c
│ └── test_program_x86_64
└── src
└── main.rs
```

Now we can start writing our Rust code. First, we need to add some dependencies
to our `Cargo.toml`.

```toml
oxidebpf = "0.1.0"
users = "0.11.0"
```

The `users` library will help us find a username from `uid` more easily. Now we
can import the libraries into our `main.rs`.

```rust
use oxidebpf::{Program, ProgramBlueprint, ProgramGroup, ProgramType, ProgramVersion};
use users::get_user_by_id;
use std::convert::TryInto;
```

Now we can start working on our main function. First we bring in the BPF
program binary and load it as a blueprint.

```c
let bytes = include_bytes!("../bpf/test_program_x86_64");
let program_blueprint = ProgramBlueprint::new(bytes, None).expect("could not read program");
```

Next, we create a `Program` from the blueprint, specifying `tcp_recvmsg` as the
attach point.

```rust
let program = Program::new(
    "trace_pid_event",
    vec!["tcp_recvmsg"],
);
```

Then we put the `Program` into a `ProgramVersion` and `ProgramGroup` (more on
that later), using the blueprint from earlier.

```rust
let mut program_group = ProgramGroup::new(None);
```

Now we put the `Program` in a `ProgramVersion` and tell the `ProgramGroup` to load
the programs from the blueprint. Since our program communicates with us, we can
get a receiving channel back.

```rust
program_group
    .load(
        program_blueprint,
        vec![ProgramVersion::new(vec![program])],
        )
    .expect("could not load program group");

let rx = program_group
        .get_receiver()
        .expect("could not get receiver channel");

And finally, we can read from the channel and display events to the end-user.

loop {
    let msg = rx.recv().expect("msg recv err");
    let pid = u32::from_ne_bytes(msg.2[0..4].try_into().unwrap());
    let uid = u32::from_ne_bytes(msg.2[8..12].try_into().unwrap());
    let user = get_user_by_uid(uid).unwrap();
    println!(
        "User [{}] '{}' received TCP in process [{}] {}",
        uid,
        user.name().to_str().unwrap(),
        pid,
        std::fs::read_to_string(format!("/proc/{}/cmdline", pid)).unwrap()
    )
}
```

The final `main()` function might look like this:

```rust
fn main() {
    let bytes = include_bytes!("../bpf/test_program_x86_64");
    let program_blueprint = ProgramBlueprint::new(bytes, None)
                .expect("could not read program");
    let mut program_group = ProgramGroup::new(None);

    program_group
        .load(
                program_blueprint,
                vec![ProgramVersion::new(vec![Program::new(
                    ProgramType::Kprobe,
                    "trace_pid_event",
                    vec!["tcp_recvmsg"],
                )])],
                )
        .expect("could not load program group");

        let rx = program_group
                .get_receiver()
        .expect("no channel returned");

    loop {
        let msg = rx.recv().expect("msg recv err");
        let pid = u32::from_ne_bytes(msg.2[0..4].try_into().unwrap());
        let uid = u32::from_ne_bytes(msg.2[8..12].try_into().unwrap());
        let user = get_user_by_uid(uid).unwrap();
        println!(
            "User [{}] '{}' received TCP in process [{}] {}",
            uid,
            user.name().to_str().unwrap(),
            pid,
            std::fs::read_to_string(format!("/proc/{}/cmdline", pid)).unwrap()
        )
    }
}
```

If we run this program in a vagrant VM, we can see SSHD receiving packets.

```
vagrant@vagrant:~$ sudo ./bpf-blog
User [1000] 'vagrant' received TCP in process [54392] sshd: vagrant@pts/0
User [1000] 'vagrant' received TCP in process [54392] sshd: vagrant@pts/0
```

From here, the sky’s the limit!

<script src="https://fast.wistia.com/embed/medias/zu6jwuuj45.jsonp" async></script>
<script src="https://fast.wistia.com/assets/external/E-v1.js" async></script>
<div class="wistia_responsive_padding" style="padding: 56.25% 0 0 0; position: relative;">
    <div class="wistia_responsive_wrapper" style="height: 100%; left: 0; position: absolute; top: 0; width: 100%;">
        <div class="wistia_embed wistia_async_zu6jwuuj45 seo=false videoFoam=true" style="height: 100%; position: relative; width: 100%;">
        <p>&nbsp;</p><p>&nbsp;</p>
        </div>
    </div>
</div>

_A quick bootstrap example showing oxidebpf loading an eBPF program that
intercepts and prints a `curl google.com` command. The eBPF program can be
found in the [redcanary-ebpf-sensor
repo](https://github.com/redcanaryco/redcanary-ebpf-sensor) under
`src/network-events.c`._

## How is the project structured?

You might be wondering why we wrapped our `Program` in a `ProgramVersion` and
loaded our `ProgramVersion` from our `ProgramGroup`. That stems from the
primary use case for oxidebpf: write once, run anywhere (ish).

A `Program` represents an individual BPF program which may or may not work across
different kernel versions. Sometimes you’ll want to collect multiple `Program`s
together to achieve some functionality, we call this a `ProgramVersion`. The idea
is that you can group `Program`s that should run together on a specific kernel
version into the same `ProgramVersion`. But you may have multiple kernel versions
deployed in your environment, which require modified BPF programs, and you
don’t want to build a separate executable for each one. This is where the
`ProgramGroup` comes in. You can have a `ProgramVersion` for each kernel in your
environment and put them all in a `ProgramGroup`. The `ProgramGroup` will attempt
to load each version in turn until one succeeds (and cleans up after itself
when they don’t).

To recap: `Program`s work together to create some desired functionality (in our
example, we have one `Program` that returns a PID and UID), `ProgramVersions`
group `Program`s together by an expected kernel version target (e.g., “this
`ProgramVersion` gets PIDs and UIDs on < 4.17, and this `ProgramVersion` gets
PIDs and UIDs on >= 4.17”), and `ProgramGroup`s combine `ProgramVersion`s to
run in as many places as possible (e.g., “this `ProgramGroup` will get PIDs and
UIDs”). The result is one executable you can run in multiple places, for
simplified deployment.

Now let’s look at the structure of the repository itself.

### `src/`

*  `lib.rs` is the main interface to the library. It’s where the `Program`,
`ProgramVersion`, and `ProgramGroup` types live. It’s also where we export
a few other types to the public interface, such as `ArrayMap`. Things like
loading logic and event polling go here.

*  `blueprint.rs` is where we parse BPF object files. It turns bytes into programs
and map definitions and helps us apply map relocations.

*  `maps.rs` handles helpers and methods that surround specific map types, such as
`PerfMap` and `ArrayMap`.

*  `error.rs` holds our custom error types.

*  The `bpf` module handles everything related to BPF system calls. Constants
go in `constant.rs`, general types in `mod.rs`, and syscall functions in
`syscall.rs`.

*  The `perf` module handles everything related to perf system calls. Similarly,
constants go in `constant.rs`, general types in `mod.rs`, and syscall functions in
`syscall.rs`.

### `test/`

*  This is where we keep the BPF program we use for running tests. Before you run
any tests on oxidebpf, you must first build the test program from this folder
with `docker-compose run --rm test-builder`.

*  The `test_program.c` provides some maps and probes for testing purposes, and the
included `Makefile` will build for both `x86_64` and `aarch64`.

### `vagrant/`

*  This folder holds various subfolders with `Vagrantfile`s you can use for running
tests on a variety of distributions and kernels. Some are happy to run under
`sudo` (Ubuntu) while some require testing as `root` (Centos and OpenSUSE).

## What's next?

One of the most common uses for BPF is to load and manage XDP programs, so one
of our immediate tasks will be to support XDP programs with the same simple
interface with which we support Kprobes and Uprobes. Instead of giving a kernel
symbol, you would give an interface and let oxidebpf take care of the rest.

After that, we will need to take care of more standard features such as
tracepoints and raw tracepoints. With those done we can move on to more
interesting security features, such as support for [Linux security
modules](https://redcanary.com/blog/linux-security-testing/).  We’re also
hoping to get feedback from the security community to learn which features are
of interest for security tooling. If you have any ideas, [submit a pull
request](https://github.com/redcanaryco/oxidebpf/pulls) or [get in
touch](mailto:rafael@ortiz.sh).

## Keeping up to date with kernel support

As the kernel evolves and new BPF features are added, popular distributions
will gradually pick up more and more BPF-related capabilities. When these new
features gain sufficient market share they can be added to oxidebpf without
breaking the goal of write once, run (almost) anywhere. Also, thanks to the
efforts of kernel maintainers, oxidebpf should retain backwards compatibility
far into the future.

## How can I contribute?

We welcome and encourage you to contribute if you find oxidebpf useful. You can
find the [repository here](https://github.com/redcanaryco/oxidebpf) and the
[code of conduct
here](https://github.com/redcanaryco/oxidebpf/blob/main/CODE_OF_CONDUCT.md).

When contributing, please keep in mind our goal of “compile once, run (almost)
everywhere.” That doesn’t mean we’ll reject newer features, like BTF support.
It just means our own contributions will prioritize stabilizing features that
are supported by as many kernel versions as possible (or at least allow it to
fail gracefully and clean up after itself if not supported). Ideally we’d like
to support any kernel version with eBPF, but a good rule of thumb is “will this
feature work or fail gracefully as early as kernel 4.4?”

Stay tuned for more updates!

