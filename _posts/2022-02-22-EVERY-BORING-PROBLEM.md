---
layout: post
title: "every Boring Problem Found in eBPF"
date:   2022-02-22 00:00:00 -0400
categories: ebpf
tags: [ebpf, tmpout]
---

**This article was originally written for tmp.0ut volume 2 and is available
here: [https://tmpout.sh/2/4.html](https://tmpout.sh/2/4.html). Due to the
unique (read: badass) format of the zine, it is replicated here as plaintext.**

# Errata

* In the section `Stable interfaces aren't`, "and on a kernel older than 4.17"
should read "and on a kernel newer than 4.16"

# Article

```
*** Looking up your article...
*** Found your article...

  :~$ head alex.ascii
                              ,,,...   ...,........
                           .*//(((((((/(((((((((####((/*,.
                     .,*/(//(//(((#%%###(##%%%##(#%%%%%#####(*..
                 .***/((//((##/###(#%&&&&%%%&%%%&&%#%%%%&&&&%%%%#/,.
               .,**/(/((##%#(((###%%%%%%&@@&&&&&&&&&&&&&@@&&&&&&&&&%(.
             ..*///#((#(((#%%%##%%%%&&&&&&@@@&&&&&&%%%&%&&&@@@@@@@&&%#*.
           ,*(/(((((((((###%%%%%%%&%%%&&%%%%%#%###((/////((##%&@@@@&&&%%(*.
        .*/(/(##(########%#%%%%%%###%%####((((///**********//(((#&&@@@&&&%(,
       .*/((##############(((////(/*******,,,,,*,,*,,,,*****/////((#%@@&&&%#(*.
     ,/(/(((####%#(((///**,,,,,,,,,,,,,,,,,,,,,*,,,,,*********//////((&@&&%%&%/.
     ,/((#((((##(((/**,,,,.....,,,,,,,,,,,,,,,,,,,,,,*************////(%&&%%%%%(.
     ,*/((##/(##(*...,........,,,,,,,,,,,,,,,,,,,,**,,,*************///(%&&%%%%%/.
   .*(##(((((#%(,.. ..  .......,,,,,,,,,,,,,,,,,,,,,,,,,***********////(#%&&%#%%%(,
   ,/(((//(##&#*,.       ....,,,,,,,.,..,,,...,,,,,,**************/////(#%&%%%%%%%#*.
   ,(##(###%&%#*.    .,*/(#%###((/*,,..,,,..,,*/((##%%%###%%####((////((#%%&%%##%%%#,
  ,(##(###&%&%#, ,////**,,,,*/(/////*,,,,,,,**/((##%%&%&&&&%%&&%&%#(///(%&&%%&%%%%%#*.
  ,(%%%#####(%(..*,,**/////*/////*/,**,.,,***/(* .*/(((#(((///*/((#%%#(((%@@%&&&&&%%#((/,
   ,(###((/.  ,,,,///(/*....,///*//(/,.,,,/((.*((/(*,/(##/,,,*((**//((((((%@&&&&@@&%(,.
    ./((((((%,,,****       /*/##(/,/*.,,***/(.. ...,(*//(#(,.,,**(((**/(((%&@&@@@@&@%*.
     ./((##%&.,,*, .      .//./(//,..**.,**/(*//*,*/(/(#((/,,,***//*,*((###%@@@@@@&&%*
      ,(##%&(.,,..,,,.       . .,.. /.,,**//#(./*,,*,,,.,.,*********,////((&@@@@@@@&&#.
       ,(##%. ,.    .     .        *.  .,**/((*.****,,,,,........,,,,**////#&@@@@@&&&(,
        .*/*   ...............  ..   ....,**//((/,*/*****,,,,,,,,,**////////&@&&&&&%,
          ,.      ........,,,.............,**//(//*/**,***,,,,,,,*//////////%&%#/*.
          ..             ..........,,,,,,*///**///****,***////***//*/*/////(%(*.
          ..          ........,.,*((#/**//##&#////*,,,,,,,*************///(#(*.
           ..      .......,,,,..,*/*,,,****/(((((/*,,,,,,,,,********/////(((/*,
           ... . .............,*(((/(//////(####//***,,,,*,,,,*****/////((#/,.
           .,............,*///(##(///(///((((##%%#((///*,,,********////((##*.
            ,,,........*/(((#(/**,,,*,,,,,,*//#%%%%%%%##(/******////((((###*.
            ,.,,,,,.,.*(((((/**//(((/,,,/**/(/(((((#%%%%%%#(//*//((((((###.
            .,,,,,.,,,(/****/#&#//***,,,,,*//*/(#%%##((((#%#(//(((((((((#(
            .,,****,,,,,,,,,...,,..,,,,*******////((///**//(#(((((#((((##*
             ,**,***,,*,,,.........,,,,********///******///*/(((#((((####.
              ,****,,,,,***,,.....,*///(((((((((//****//(((/(((###(###%%/.
               .****,,,*/((/*,,....,*//(#((//****/*///(######(((#(##%%&%(.
                 ,*//**/((#((/*****//*//////////(#(##%%%%&%####%#&%&&%/,
                   *##########((**//////(/((/(/#(##%%&&%&&&&%&&&&&&&#,
                    ,#%%&%%%###(((((((//((((((###%%%&&&&&@@&@@@&&&%(,
                      ,/#%&%%%#(##(#(#((########%#%%&&@&@@@@&@&&%#*.
                        .*(%&&%%###(####%#%%###&%&&&@@@@@&&&&%%%#/,
                           .,*(%&&%%%%&%&&&&&&&&&@@@@@&&&&%&%(*.
                                .,*(##%%&%%%&%&&%%%%#((///*,.
                                      .

        ~~[every Boring Problem Found in eBPF] by @FridayOrtiz~~

> /WHOIS @FridayOrtiz
*** @FridayOrtiz https://ortiz.sh/contact/
> /LIST
*** eBPF, BPF, Linux Kernel, guide, tips

+-#- Introduction -#-
|
| About six months ago I started a new job and dove into adding Berkeley Packet
| Filters (BPF) as a telemetry source for our Linux endpoint security agent. This
| work culminated in the release of three open source libraries ([0], [1], [2]).
| This isn't about that, though. This is about the issues we ran into while
| implementing BPF as defenders, and how defenders can use BPF in their
| environments (although attackers should find useful tips in here too). I went
| through every PR, Jira ticket, and message from the past six months to put
| together this list of BPF gotchas and their solutions. I hope it helps
| defenders, developers, and researchers ramp up with BPF faster than I did.
|
| Note: I'm going to use BPF to mean extended BPF (eBPF), since that's the
| official name. Not to be confused with the old classic BPF (cBPF). I'm also
| going to assume you're *loosely* familiar with BPF, enough to be considering
| whether or not to deploy it in your environment.
+-

+-#- Why even use BPF? -#-
|
| You may be wondering, "if you're filling an article with caveats about BPF, why
| should I even bother trying to use it?" Great question, straw man. There are a
| number of things BPF is really, really, good at that you should consider.
|
| - **You can get visibility (almost) anywhere you want.** If there's a specific
| code path within the kernel (or userspace) that you know will be executed during
| an attack, you can put yourself there. If there's a payload value in a packet
| you need to see before it hits your `iptables` rules, you can do that. Want to
| modify or block syscall args? You can do that too.
|
| - **You can reinstrument dynamically.** Change your mind about what you want to
| inspect? Change it while it's running. You can either swap out the entire
| program (although that might not be possible in the future with signed BPF
| programs[4]) or modify behavior by updating BPF maps from userspace.
|
| - **It's safe!** You can do all these things with a Linux Kernel Module (LKM),
| sure, but the BPF Virtual Machine (BPF-VM) and verifier ensure (or at least
| try really hard to ensure[17]) that you can't panic or break the kernel.
|
| - **It's container aware, or at least it can be**. Instrumentation alternatives
| like `auditd` tend to struggle in containerized environments, returning values
| that only make sense in certain namespaces, or losing track of things entirely.
| BPF, on the other hand, can give you information in whatever context you want
| (as long as you program it that way).
|
| - **It's fast.** Do as much work as possible in the BPF program before sending
| information up to userspace, and you can avoid expensive context switching or
| race-prone data enrichment.
|
| - **It's atomic (sort of).** BPF programs generally aren't preemptable (there
| are exceptions[5]). This applies to tail calls as well, so you can set up some
| fairly complex logic in your instrumentation without worrying too much about
| reentrancy.
+-

+-#- The problem with BPF. -#-
|
| From this writer's perspective, there are two main problems with BPF: 1) it's
| now being used in ways it was never designed for (i.e., it's evolving naturally
| over time) and 2) there's a large overlap in maintainers of the Linux kernel's
| BPF subsystem and userspace BPF tooling.
|
| The following are concrete issues stemming from (1):
|
| - BPF isn't really CO-RE (Compile Once - Run Everywhere), it's more CE-RO
| (Compile Everywhere - Run Once). A lot of userspace tooling "achieves" CO-RE in
| practice by compiling on the host machine. New true CO-RE features are... new.
| Chances are you need to support a kernel that doesn't have them. End-of-life
| doesn't mean much when the host is running a business-critical function and the
| suits see too much risk in upgrading it. And loading a full toolchain to
| compile BPF programs on the host is often a no-go too.
|
| - The toolchains and libraries are designed around `bpftrace`-like use cases.
| That is, one-off tooling for diagnosing specific problems. Brendan Gregg's
| book[7] is a great resource for this. Now that BPF for long-running daemons is
| gaining popularity, the maintainers are working hard adding features to support
| this (like the aforementioned true CO-RE). Unfortunately, again, these features
| probably won't exist on the kernels you need to support.
|
| - There are many different types of BPF programs (which we'll cover), that all
| have varying load and run semantics. Depending on whether you want to run a
| kprobe or a TC classifier, you'll have to use entirely different methods to do
| so. And while you're writing them, the helpers available to you can vary
| wildly. And the documentation is incomplete, scattered, and often out of date,
| because...
|
|
| And here are some specific examples of issues stemming from (2):
|
| - Because of the overlap, documentation of the pure BPF interface(s) (there's a
| plethora, we'll cover that) is lacking. The people that maintain it write the
| userspace tooling, so they don't need in-depth documentation. Seriously, go
| check out the BPF manpage for whatever distro you're on. Chances are it's
| missing a ton of helpers and there's more than one "TODO: fill this out" that's
| been sitting there for years. Why not use their userspace tooling? Well...
|
| - Their userspace tooling is a magic labyrinth. In order to get close to CO-RE in
| a backwards compatible way, it's filled with kludges you probably don't need.
| Ideally, you'd interface directly with the underlying syscalls and use only
| what you need. But doing that is undocumented. And, because of the
| documentation issues, there's really no community drive to simplify these
| libraries. Because these libraries cover (until recently, see (1)) the majority
| of historical use cases, there's no drive to improve the documentation. Even if
| you did, you'd have to backport and patch your documentation to cover all the
| little idiosyncrasies across kernel versions, and boy are there a lot of those.
+-

+-#- Implementation Issues -#-
|
| While working with BPF we ran into a number of implementation specific problems
| that lead to us building and publishing those three ([0], [1], [2]) BPF tools.
| If you're a defender, or work in security, and you're considering getting
| started with BPF here's a list of things you'll probably want to know.
| Presented in somewhat logical order.
|
| +-**- The verifier sucks, but the alternatives are worse. -**-
| |
| | -...- Problem -...-
| |
| | You will run into lots of problems with the verifier. For example, what's the
| | difference in the following two code snippets?
| |
| | ```c
| | u32 *p = 1;
| | u32 i = *p;
| | ```
| |
| | ```c
| | u32 *p = 1;
| | u32 i = NULL;
| | __builtin_memcpy(&i, p, sizeof(u32));
| | ```
| |
| | I'll tell you: the first one fails the verifier, the second one does not. But
| | only sometimes, except when it works. Which depends on the kernel version.
| | Maybe. I mean, they should compile to the same thing, right? Apparently not,
| | and subtle differences can completely throw the verifier off.
| |
| | The real problem with the verifier is that it's getting better all the time. As
| | BPF use cases settle out, the maintainers are changing the BPF verifier to
| | better support them. That means on older kernel versions, without these
| | patches, you'll have to perform strange workarounds to get your code working
| | with older verifiers.
| |
| | A few more verifier problems you'll likely encounter supporting a wide range of
| | kernel versions:
| |
| | - The verifier hates looping. But, sometimes, it also hates loop unrolling. If
| | `clang` generates enough jumps and gotos, even if you tell it to unroll
| | everything, the verifier might (depending on version) fail it anyway. The
| | verifier needs to be able to keep track of all branches and ensure a maximum
| | depth limit. If it can't (whether it's because you're looping or because the
| | verifier can't keep up) your program will fail to verify.
| |
| | - In older kernel versions (but not newer ones) variable reads and writes are a
| | big no-no. All offsets must be known at compile time. That means you can't do
| | things like set `some_array[variable_index] = some_value`. This, plus the
| | aversion to loops, makes it nearly impossible to read strings from memory on
| | kernels without the `read_str` family of helpers. The kernel's own `qstr`
| | involves variable memory access—and good luck finding (or setting) the null
| | terminator on your own.
| |
| | - Everything that might be a pointer must be null checked. If you don't, the
| | verifier will refuse to load your program even if it's safe. This makes it hard
| | to work with programs that might expect a null value. The convention that most
| | pleases the verifier is to return immediately after a failed null check, and
| | getting around this is tricky and involves trial and error.
| |
| | There are alternatives to the kernel verifier, such as PREVAIL[8], but they
| | have their own set of issues. For what it's worth, PREVAIL is an impressive
| | project and Microsoft will be basing their Windows BPF verifier off of it. But,
| | unfortunately, it doesn't match the expected behavior of kernel verifier. Just
| | because something passes PREVAIL doesn't mean it will pass the kernel verifier.
| | Just because something fails PREVAIL doesn't mean it will fail the kernel
| | verifier (even though it probably should).
| |
| | -...- Solution -...-
| |
| | **Run early, run often, run everywhere.** Your development environment should
| | make it as easy as possible to test your code on all the kernels you need to
| | support (or as close to a representative sample as you can get). The only way
| | to know if the kernel verifier will accept your program is to run it through
| | the kernel verifier, the real kernel verifier, on the specific kernel you're
| | targeting. Note that this means the distro-specific kernel, with all their
| | modifications and backports. For example, the older Enterprise Linux (red hat,
| | centos, and so on) kernels (2.x and 3.x) have backported BPF features that
| | might surprise you, since they don't line up with mainline kernel version
| | numbers. The only way to know what's supported is to try it.
| |
| | **Enable logging.** This one comes with a caveat. You need to provide the
| | verifier with a large buffer of memory to write its verification logs into. If
| | you don't give it enough space it will fail verification, even if the program
| | would otherwise pass. If your programs are complex, then make sure your buffer
| | is large enough (but not too large, or loading will take forever) and be sure
| | to turn off verifier logs in production to avoid issues with programs failing
| | to load when you know they should.
| |
| | **The error messages you get will seem cryptic at first.** The BPF verifier
| | uses a lot of terminology and has a lot of restrictions that are undocumented
| | (of course) that you'll learn with time. If you get stuck, the BPF Compiler
| | Collection (BCC) GitHub repo's issue tracker[9] is a great resource. You can
| | probably find a Brendan Gregg ticket that goes over at least the broad class of
| | error you're getting.
| +-
|
| +-**- BPF doesn't really exist. -**-
| |
| | -...- Problem -...-
| |
| | BPF is really just an instruction set, for which the Linux kernel provides a
| | VM, verifier, and some helper functions. You run your programs inside this
| | execution context, and call the helper functions to extend the VM's
| | capabilities. When you write a BPF program, what you're really writing is a
| | kprobe, or a uprobe, or an eXpress Data Path (XDP) classifier, or a Traffic
| | Control (TC) classifier, or one of the many other types of kernelspace programs
| | that have been offloaded to the BPF subsystem. There's a ton of BPF program
| | types and more are being added all the time, for a variety of use cases. It
| | turns out being able to safely execute code in the kernel enables a ton of
| | interesting and helpful functionality. Unfortunately, every program type has
| | its own way to load, run, and clean up after it, most of which is entirely
| | undocumented.
| |
| | On certain distros, the tools you'll need to load these programs might not be
| | enabled by default. For example, some distros don't automatically mount
| | `debugfs`, which you'll need to load kprobes on older kernels.
| |
| | When you do figure out how to load your program, the ABI for defining programs
| | is entirely based on undocumented, implicit, convention. For example, you'll
| | see a lot of `SEC("kprobe/my_kprobe")` to tell the loader that you're loading a
| | kprobe.
| |
| | ```c
| | /* helper macro to place programs, maps, license in
| |  * different sections in elf_bpf file. Section names
| |  * are interpreted by elf_bpf loader
| |  */
| | #define SEC(NAME) __attribute__((section(NAME), used))
| | ```
| |
| | This is actually entirely unnecessary, on the syscall level, and is merely a
| | common convention. As you can see in the above snippet, it's just a macro to
| | set the section name in the compiled ELF executable. There's nothing
| | BPF-specific about it. So you not only have to know the requirements of the
| | program type you're trying to load, but also the conventions used by the tools
| | that load and run it.
| |
| | -...- Solution -...-
| |
| | Figure out what you want your program to do first. Do you want visibility into
| | the kernel? Then you'll probably want a kprobe or tracepoint. Do you want to
| | drop inbound packets? You probably want XDP. Do you want to build detections on
| | outbound traffic? You might want TC, or you might want a kprobe in the kernel
| | network stack. Figure this out, then figure out what you're going to need to
| | run it the way you want to run it (one off? daemon?). When we made `oxidebpf`
| | we had to optimize for stability in the features we needed most (e.g., kprobes)
| | over coverage of all the different BPF program types.
| |
| | If you can't find libraries to suit your needs for your chosen program type,
| | you'll probably have to write it yourself (or contribute it to an open source
| | project). Because everything is poorly documented, you'll have to dig through a
| | lot of source code to put together the real set of necessary functionality. The
| | official-ish libraries like libbpf and libbcc tend to work the best, but
| | there's issues there (that we'll get to).
| |
| | I highly recommend using `bpftool` for debugging while developing. It provides
| | the easiest-to-use view into what programs and maps are loaded and where. It
| | lets you visualize data in maps, dump programs, and more. The only problem with
| | `bpftool` is that it's never in the same package. Some distros and repos let
| | you install it with a `yum install bpftool`. Others require you `apt-get
| | install linux-oem-tools`. Sometimes you need to `apt-get install
| | linux-oem-tools-`uname -r``. It depends. Whatever you're running, though,
| | you'll probably want this tool installed.
| +-
|
| +-**- I hope you find constraints fun. -**-
| |
| | -...- Problem -...-
| |
| | Are you one of the dozen or so people unreasonably upset that `0x10c`[10] was
| | never released? Me too! I find working within constraints challenging and
| | enjoyable. And let me tell you, BPF programs have a lot of constraints.
| |
| | You get 512 bytes of stack space for your program, half a kilobyte. This
| | doesn't appear to be something that has or will ever change. It's also unclear
| | if this applies to tail calls. Some documentation implies that tail calls use
| | the same stack space, so you're limited to 512 bytes total, but in practice it
| | seems to be 512 bytes per program. And `clang` probably won't be able to help
| | you. BPF programs, for whatever reason, don't like to reclaim stack space. Your
| | variables will get hoisted and instantiated at the start of execution. If you
| | want to do things like dump syscall arguments or `pt_regs`, especially when
| | working with strings, you'll find yourself running out of stack space very
| | quickly.
| |
| | There's a practical instruction limit of about 4096 instructions. The
| | instruction limit in the past was set (as far as I can tell) based on what the
| | verifier could verify before declaring "this has gone on too long, I can't
| | verify this won't halt, so I'm failing it." You can get more instructions by
| | manipulating the verifier, and doing other tricks you'll find in the mailing
| | lists, if you really want to put in the effort. Newer verifiers let you get
| | upwards of 1,000,000 instructions, but that'll only help you if you're
| | supporting newer kernels.
| |
| | -...- Solution -...-
| |
| | To work around the instruction limit, you can use tail calls. Tail calls are
| | the closest BPF has to a true function call. You transfer flow over to
| | whichever program you call into. You can chain tail calls like this together up
| | to 33 times. There are some caveats, which we'll get to later.
| |
| | There are a few tricks you can use to work around the stack limit. One trick is
| | to explicitly reuse stack space. For example, reusing variables or
| | instantiating a struct of bytes to act as your scratch space and manually
| | reusing offsets within it. Another trick is to build your own stack with maps.
| | On some kernel versions you can request a struct from a map and get a pointer
| | to it. If the requested struct doesn't exist (e.g., the array map at the
| | requested index was empty) you'll still get back a pointer to an empty struct
| | that you can manipulate. Other kernel versions require this map-struct to be
| | copied to the stack before being modified, so your mileage may vary.
| |
| | With all that said, I want to offer some practical advice. If the information
| | you're retrieving is too big to ever fit on the stack, you should just send it
| | out as you read it. Create a messaging type and pipeline for chunking and
| | rebuilding data in userspace, copy as much as you can to the stack, and then
| | send it up through a map. This will run on a wider range of kernel versions,
| | and you won't have to worry about if your host kernel allows directly
| | manipulating and emitting map memory. You can reconstruct it in userspace at
| | will. This is what companies like Google are doing for their BPF telemetry.
| +-
|
| +-**- The good stuff is GPL. -**-
| |
| | -...- Problem -...-
| |
| | All the useful helper functions (like `perf_event_output`[6]) are exported as
| | GPL-only. If you want your program to do anything useful, you're going to have
| | to license it under GPL. That makes it hard to make proprietary programs based
| | on BPF. If your program is only internal, and never distributed, you're fine.
| | But if you start distributing your programs (to customers, friends, wherever)
| | you need to publish it under GPL.
| |
| | -...- Solution -...-
| |
| | Short answer: Make the world a better place, release your BPF code and tools.
| |
| | Long answer: BPF is still a niche and complex discipline, so open sourcing your
| | tooling doesn't reduce competitive effectiveness for a business. From an
| | individual perspective, open sourcing your tooling gets your name out there and
| | makes you more valuable as an employee. From an employer perspective, the more
| | accessible BPF becomes the easier it will be to hire people to build and
| | maintain it. From the community perspective, we can all learn from each other
| | by working in the open. Perhaps you have an interesting use case that the
| | maintainers of other libraries would want to know about, or could offer advice
| | on. Everybody wins.
| +-
|
| +-**- By default, you get the default. -**-
| |
| | Alternatively, BPF is only good with containers if you tell it to be.
| |
| | -...- Problem -...-
| |
| | Be careful with the assumptions you make about the information you retrieve
| | from a BPF program. If you grab the retcode of a `fork` call, it's going to
| | give you the retcode of the `fork` call: the pid in the namespace of the
| | calling process. Maybe this is what you wanted, or maybe you really wanted the
| | pid of the child process un-namespaced. Maybe you ask the BPF program to gather
| | the pid (with the `get_pid_tgid` helper). You take the upper 32 bits,
| | corresponding to the pid, but nothing lines up. Well, you're executing in
| | kernelspace which means the `pid` you probably want is actually the `tgid`, and
| | what you got was a `tid`. Unless you wanted a `tid`, in which case you should
| | get the `pid`. The kernelspace understanding of a `pid` is not the same as the
| | userspace understanding of a `pid`. If you want to identify a file, you
| | probably want the inode number and device number, a file descriptor won't be as
| | useful.
| |
| | -...- Solution -...-
| |
| | If you want your program to retrieve information, think about what information
| | you need to retrieve. Make sure you know where that information exists (what
| | structs, where they live in memory, and how to get there) and then find a place
| | (assuming you're launching a kprobe) in the kernel you can attach your program
| | as close to that information as possible. For example, if you really need the
| | root namespace pid of the child process of fork, you probably want to hook
| | somewhere in the path of the new child process so you can grab the `pid` from
| | the `task_struct`.
| |
| | Be aware that this location might change between kernel versions, or the
| | information may take a different form. You may have to choose a less optimal
| | probe point that is available on more systems. Or you may have to change the
| | information you're gathering to something else that exists on all the kernels
| | you support. That leads us to the next two issues.
| +-
|
| +-**- CO-RE (probably) won't help you. -**-
| |
| | -...- Problem -...-
| |
| | The maintainers are constantly adding feature to help BPF developers compile
| | once-run everywhere their BPF programs. Unfortunately, you'll likely find
| | yourself trying to target kernel versions that don't have these features. Or,
| | if you do, since these features are added in piecemeal, it may not have all the
| | CO-RE features you expect.
| |
| | For example, the BTF feature makes it possible to reference struct members
| | directly, even if they've been compiled in a randomized layout, across
| | different kernel versions, and without recompiling. This feature was added in
| | April of 2018[11]. You will probably need to write code for kernels from before
| | April 2018. This means something like `current->real_parent->pid` is not
| | guaranteed to work without recompiling for (or on) the host.
| |
| | -...- Solution -...-
| |
| | There's really no way around this one. It's what we're doing, Microsoft is
| | doing it too for their Linux machines, and I'm sure there are others. First,
| | you determine the offsets of struct members for your desired kernel version and
| | then you load them dynamically into your BPF program at runtime. For example,
| | this code snippet from [12] shows how we read struct offsets from a map and use
| | that in our `bpf_probe_read` to retrieve values.
| |
| | ```c
| | static __always_inline int read_value(
| | 		void *base, u64 offset, void *dest, size_t dest_size
| | )
| | {
| |     /* null check the base pointer first */
| |     if (!base)
| |         return -1;
| |
| |     u64 _offset = (u64)bpf_map_lookup_elem(&offsets, &offset);
| |     if (_offset)
| |     {
| |         return bpf_probe_read(dest, dest_size, base + *(u32 *)_offset);
| |     }
| |     return -1;
| | }
| | ```
| |
| | To actually find these offset values in the first place, we built the
| | `linux-kernel-component-cloud-builder`, or `LKCCB`, which builds hundreds if
| | not thousands of kernel modules with debug enabled for all our target kernel
| | versions and extracts structure offset information from the LKM's `DWARF` debug
| | info[1].
| +-
|
| +-**- Stable interfaces aren't. -**-
| |
| | -...- Problem -...-
| |
| | You'll often find, when working with the kernel, that there aren't as many
| | stable interfaces as you thought there'd be. Even syscalls, which are supposed
| | to be a big part of the stable user interface, aren't necessarily stable.
| |
| | For example, if you somehow traveled back in time and wanted to monitor process
| | forks, you'd probe the `fork` syscall. That'd work fine for a bit, until
| | `clone` is introduced. If you stopped paying attention, you'd lose your data
| | altogether when glibc (and everything with it) switched `fork()` to be a
| | wrapper around `clone()`.
| |
| | Maybe you want to get the arguments of a syscall. Should be easy, you're given
| | `pt_regs`, just access the registers that hold the arguments! Except if you're
| | on x86_64, and on a kernel older than 4.17, you'll probably be given the
| | `pt_regs` of the syscall wrapper function, that in turn calls the real syscall
| | function. And of course, it all shuffles around if you need to add aarch64
| | support, which has its own set of calling conventions.
| |
| | Sometimes a symbol that's marked as being exported can't be attached to, almost
| | inexplicably. Usually this is due to GCC inlining the function, and the symbol
| | being renamed to something like `symbol_name.part.1213`.  Trying to bind
| | `symbol_name` won't work.
| |
| | -...- Solution -...-
| |
| | For different architectures you can probably get away with macros that
| | conditionally compile depending on what architecture you're targeting, and then
| | building one copy per architecture. For the syscall wrappers, you can do
| | something similar but build targeting different kernel versions. In practice,
| | you may find you need many variants and copies of a single program, all with
| | slight differences, to support different kernels and architectures.
| |
| | For the symbol name problem, it comes back to run early and run often. It's
| | often worth spinning up a VM of a few of the kernels you're targeting and
| | double checking that the locations you're hooking are indeed in
| | `/proc/kallsyms`. Sometimes you'll find the functions you were looking at don't
| | exist in different versions, or have been renamed and relocated. I recommend
| | getting comfortable with Bootlin's Elixir cross referencer (but you still need
| | to run and see, because distros do their own backports which won't match what's
| | in the mainline cross referencer).
| +-
|
| +-**- Running BPF programs as intended involves magic. -**-
| |
| | -...- Problem -...-
| |
| | If you use libbcc, libbpf, bpftrace, or any other other high level BPF tools
| | you'll quickly notice that they do a lot of magic for you. BCC (the python
| | interface) will more or less rewrite your programs for you so they work on your
| | host system. You'll end up getting error messages on code that the library
| | wrote for you. They also help you get around CO-RE limitations by compiling on
| | the host, and using different tricks and kludges to get the same program code
| | to operate in many environments as cleanly as possible. This doesn't help a ton
| | when you need to build and distribute actual raw BPF programs in their own ELF
| | file.
| |
| | These libraries are also pretty convoluted. There's a lot of overlap in
| | maintainers between these libraries and the people working on BPF in the
| | kernel, so documenting the interactions isn't a priority. But you don't
| | actually need all the stuff these libraries are doing. After a while,
| | especially with the rewriting, you'll find yourself wanting to write and load
| | pure BPF C code. Here's a snippet of a map I put together when trying to figure
| | out what syscalls were actually being made when libbpf loaded a program.
| |
| | ```
| | KProbe
| |   |-> bpf_attach_kprobe()
| |       |-> bpf_attach_probe()
| |           |-> bpf_try_perf_event_open_with_probe()
| |               |-> bpf_find_probe_type()
| |               |-> bpf_get_retprobe_bit()
| |               |-> syscall(__NR_perf_event_open)
| |           |-> create_probe_event()
| |               |-> enter_mount_ns()
| |                   |-> setns()
| |               |-> exit_mount_ns()
| |                   |-> setns()
| |           |-> bpf_attach_tracing_event()
| |               |-> ioctl( PERF_EVENT_IOC_SET_BPF )
| |               |-> ioctl( PERF_EVENT_IOC_ENABLE )
| |           |-> bpf_close_perf_event_fd()
| |               |-> ioctl( PERF_EVENT_IOC_DISABLE )
| | ```
| |
| | These libraries are also GPL, which means your userspace program would end up
| | being licensed under GPL and not just your BPF programs. As great as this is
| | for users, if you work for a company that likes to make money you might not be
| | allowed to touch GPL. It might even be in your contract.
| |
| | -...- Solution -...-
| |
| | If you're writing complex BPF programs for security, you'll probably want to
| | write it in C without the "help" of something like BCC. You'll also want a bit
| | more control and transparency when loading and attaching your programs. In my
| | experience, libbpf wasn't great at cleaning up after itself and it got
| | frustrating.
| |
| | Use a clean, simple, library built from the ground up for loading BPF in your
| | language of choice. For Rust, `aya`[16] is a good one, and I worked on
| | `oxidebpf`[0]. Golang also has some good options. One common theme of these
| | projects is the amount of effort that went into reverse engineering the
| | undocumented program loading logic and reimplementing it. Take advantage of
| | that work and use it to load your programs. They're also permissively licensed!
| +-
|
| +-**- Speed kills. -**-
| |
| | -...- Problem -...-
| |
| | After getting into BPF, you may benchmark a few of your programs and be
| | surprised at how much faster BPF is than what you've been using before, like
| | audit. This makes it very tempting to trace and probe more than you probably
| | should. For example, if you want to trace socket closes you may be tempted to
| | put a kprobe on the `close` syscall. This syscall is called all the time, and
| | probing it will slow your system down unnecessarily. Most of the messages will
| | be discarded since you only care about sockets. There are plenty of other
| | interesting areas that can't be reasonably instrumented due to the performance
| | impact.
| |
| | -...- Solution -...-
| |
| | Trace only what you need, and scope it down as much as possible. Going back to
| | the `close` example, you'd be better off probing somewhere downstream where the
| | individual `tcp_close` or `udp_close` functions are called.
| |
| | ```
| | struct proto tcp_prot = {
| | 	// ...
| | 	.close			= tcp_close,
| | 	// ...
| | };
| | EXPORT_SYMBOL(tcp_prot);
| |
| | struct proto udp_prot = {
| | 	// ...
| | 	.close			= udp_lib_close,
| | 	// ...
| | };
| | EXPORT_SYMBOL(udp_prot);
| | ```
| |
| | Brendan Gregg's book[7], again, has a great table that shows the overall
| | performance impact of tracing different points in the kernel. You could also
| | just reason intuitively about how often you think each area you want to probe
| | is exercised. The more commonly a code path is executed, the more expensive it
| | will be to probe it.
| |
| | Even after doing your best to scope down and optimize your BPF programs, you'll
| | probably want to run benchmarks as you tweak things to see what performs best
| | in your target environment. Flamegraphs[13] are a great way to see where most
| | of your overhead is coming from, especially if combined with a benchmarker like
| | UnixBench[14]. The results may surprise you.
| |
| | I'd also recommend processing BPF events in batches. You'll probably be sending
| | out a lot of information through maps that needs to be read from userspace. If
| | you're getting information that's too big for the stack, the information will
| | be sent in chunks that need to be reconstructed in userspace. It's definitely
| | possible to loop a blocking poll+read on the perfmap or BPF ring buffer, but
| | doing so will result in significant overhead. You're much better off letting
| | the buffers fill a bit, and processing them in batches (batch process, don't
| | stream process). Doing that netted me significant performance gains in
| | benchmarks for the BPF programs I write at work.
| +-
|
| +-**- Don't Panic. -**-
| |
| | -...- Problem -...-
| |
| | BPF programs will generally live as long as something holds a file descriptor
| | that points to them. However, sometimes you need to manually clean up after
| | them (such as when using `debugfs`). If your userspace program crashes or
| | panics things may not get cleaned up properly. This can lead to all sorts of
| | problems when you restart your probes, such as receiving duplicate events.
| |
| | If you're building short lived, one off, tools this is less of a concern. But
| | if you're managing several probes as part of a long-lived monitoring daemon
| | then this is something you need to be careful with.
| |
| | -...- Solution -...-
| |
| | Make sure you design the userspace component of the BPF program to keep your
| | programs alive for as long as you'll need them. Gracefully handle all errors in
| | the thread that keeps your BPF programs alive and make sure you clean up after
| | yourself in the event of failure or shutdown. Keep in mind that many older BPF
| | tools are built around short-lived programs, meant for things like `bpftrace`
| | or production debugging.
| +-
|
| +-**- Know your limits. -**-
| |
| | -...- Problem -...-
| |
| | Your program will have instructions and will probably use maps. These take up
| | space, which the BPF syscall will handily memlock for you. On many distros,
| | this is fine. On others, however, the default memlock ulimit is quite low[15].
| | See the following output of `ulimit -l` on various distributions.
| |
| | ```
| | vagrant@ubuntu2004:~$ ulimit -l
| | 65536
| | [vagrant@centos7 ~]$ ulimit -l
| | 64
| | vagrant@opensuse15:~> ulimit -l
| | 64
| | ```
| |
| | If you can't memlock enough memory to fit your instructions and maps, you'll
| | get rejected with cryptic verifier error messages.
| |
| | -...- Solution -...-
| |
| | Calculate the amount of memory your programs and maps will need, and check the
| | memlock limits on your target systems. You may be fine, or you may need to
| | raise it first. Some libraries (like the one we wrote![0]) can try to take care
| | of this for you.
| +-
|
| +-**- Tail calls aren't guaranteed. -**-
| |
| | -...- Problem -...-
| |
| | Think of tail calls like the BPF equivalent of `execve`, except less powerful.
| | It'll start running a new probe, with the original context argument, and
| | replace everything you were previously doing. You can't provide it with custom
| | arguments, and the tail call needs to pass the verifier independently. This
| | means if you want to communicate between tail calls you'll need to use maps.
| | You're also limited to chaining 33 tail calls in a single execution, after that
| | the tail call execution will simply fall through.
| |
| | You can't call into another program with a tail call directly, either. You need
| | to reference an index in a tail call program map (a type of BPF map) which
| | needs to be set from userspace. For example, if you want to tail call from
| | `prog_a()` into `prog_b()`, you'll need to load `prog_a()` and `prog_b()`
| | first. At this point if `prog_a()` fires, the tail call into `prog_b()` will
| | fizzle. Then, from userspace, you need to update a map to say "`prog_b()` is at
| | index 5, if anyone tries to tail call into index 5, send them to `prog_b()`."
| | Tracking and maintaining all these indexes can be cumbersome.
| |
| | And there's not always a guarantee that the tail call will fire. You could
| | reach an execution limit, or a memory limit, or some other weird verifier edge
| | case that prevents the tail call from firing. Your programs need to handle this
| | gracefully.
| |
| | -...- Solution -...-
| |
| | First, you'll have to write your tail calls as though they were independent
| | programs. Think of designing each one to grab a different bit of information
| | you're looking for. If you find yourself re-calculating the same things in each
| | program or otherwise need to communicate across calls, store and retrieve
| | information from a map.
| |
| | For managing indexes, use an enum for your tail calls and reference that from
| | your userspace application. For example, have an `enum tail_calls { PROBE_A,
| | PROBE_B };` and then reference it from inside your programs and when loading
| | the program map from userspace. The file descriptor for `probe_a()` goes at
| | index `PROBE_A`, and so on. If you want to call into `probe_a()`, you get there
| | by asking for `PROBE_A` with `bpf_tail_call(ctx, &tail_call_table, PROBE_A);`.
| |
| | Your program should also have a plan for what happens if the tail call doesn't
| | go off. Do you want to send up an error? Ignore it? Send up a message that
| | execution was completed? Something else? For example, if you're using recursive
| | tail calls to read a string value you may want to return a message that says
| | you hit your tail call limit before you finished reading the string.
| +-
|
| +-**- You can't just return what you want. -**-
| |
| | Alternatively, you're on your own with error handling.
| |
| | -...- Problem -...-
| |
| | This one was a problem that we didn't even realize we had because it was so
| | subtle. In C it's pretty customary to return `0` on success and `-1` (or some
| | other negative error code) in the event of a failure. The actual returned value
| | is usually written to a buffer or some other pointer given as a function
| | parameter. You check the return code for success or failure and take actions
| | appropriately (in theory). While writing BPF programs in C, especially kprobes,
| | you might be tempted to follow this pattern. After all, it makes sense. The
| | actual value you return is sent out through perf or written into a map so
| | userspace can grab it, so the return value of the probe itself should be `0` to
| | indicate success or `-1` to indicate failure, right?  Just like every other C
| | program? Wrong! For program types other than kprobes (remember, BPF is just an
| | execution environment) it's more obvious that the return codes have special
| | meaning.  For example, XDP programs have explicit return codes to drop, pass,
| | or re-process packets.
| |
| | For kprobes, `return 0;` means "I'm done with this kprobe, you can move on."
| | You indicate that you want to keep the probe hanging around with _literally any
| | other return code_ (including `return -1;`).  That's probably not what you
| | want. Take a look at this function from the kprobe handler in [18]:
| |
| | ```c
| | /* Kprobe profile handler */
| | static int
| | kprobe_perf_func(struct trace_kprobe *tk, struct pt_regs *regs)
| | {
| | 	// ...
| | 	if (bpf_prog_array_valid(call)) {
| | 		// ...
| | 		ret = trace_call_bpf(call, regs);
| |		// ...
| | 		if (!ret)
| | 			return 0;
| | 	}
| |
| | 	head = this_cpu_ptr(call->perf_events);
| | 	if (hlist_empty(head))
| | 		return 0;
| |
| | 	dsize = __get_data_size(&tk->tp, regs);
| | 	__size = sizeof(*entry) + tk->tp.size + dsize;
| | 	size = ALIGN(__size + sizeof(u32), sizeof(u64));
| | 	size -= sizeof(u32);
| |
| | 	entry = perf_trace_buf_alloc(size, NULL, &rctx);
| | 	if (!entry)
| | 		return 0;
| |
| | 	entry->ip = (unsigned long)tk->rp.kp.addr;
| | 	memset(&entry[1], 0, dsize);
| | 	store_trace_args(&entry[1], &tk->tp, regs, sizeof(*entry), dsize);
| | 	perf_trace_buf_submit(entry, size, rctx, call->event.type, 1, regs,
| | 			      head, NULL);
| | 	return 0;
| | }
| | ```
| |
| | There's two things you should notice in that snippet. The line `ret =
| | trace_call_bpf(call, regs);` and `if (!ret) return 0;`. That means if
| | `trace_call_bpf()` returns _anything but `0`_ (including `-1`) we go through
| | the remainder of the function, buffer allocation, trace argument storage, and
| | so on. We can grab the internals of that function at [19]:
| |
| |
| | ```c
| | /**
| |  * trace_call_bpf - invoke BPF program
| |  * @call: tracepoint event
| |  * @ctx: opaque context pointer
| |  *
| |  * kprobe handlers execute BPF programs via this helper.
| |  * Can be used from static tracepoints in the future.
| |  *
| |  * Return: BPF programs always return an integer which is interpreted by
| |  * kprobe handler as:
| |  * 0 - return from kprobe (event is filtered out)
| |  * 1 - store kprobe event into ring buffer
| |  * Other values are reserved and currently alias to 1
| |  */
| | unsigned int trace_call_bpf(struct trace_event_call *call, void *ctx)
| | {
| | 	unsigned int ret;
| |
| | 	// ...
| |
| | 	/*
| |      * ...
| | 	 */
| | 	ret = BPF_PROG_RUN_ARRAY(call->prog_array, ctx, bpf_prog_run);
| |
| | 	// ...
| |
| | 	return ret;
| | }
| | ```
| |
| | As you can see, this is the function that actually invokes the kprobe. It gets
| | `ret`, which it returns, from `BPF_PROG_RUN_ARRAY()` which, as you might
| | expect, runs the BPF program. The documentation on this function is also pretty
| | explicit, which is nice. When we return `0`, we've returned from the kprobe and
| | don't need to keep any details about it hanging around. When we return `1`
| | (which anything besides `0` aliases to) we store information about the kprobe
| | in a ringbuffer for later.
| |
| | -...- Solution -...-
| |
| | The solution here is to always `return 0;` in your kprobes, unless you have an
| | explicit need to `return 1;`. If you want to know if your kprobe failed or is
| | in some incomplete state, you'll need to architect your message-passing to
| | handle that case. For example, you might want to include a success code flag in
| | the struct(s) you pass through a perfmap which you can check for failure. Or
| | you might want to build your system around a best-effort event reconstruction
| | for more complicated returns involving multiple messages. In any case, you'll
| | have to engineer your error checking and handling independently of the BPF VM
| | system. Those return codes are reserved, you gotta make your own.
| +-
+-

+-#- Wow, that looks hard. Can you summarize it for me? -#-
|
| Certainly! BPF is really good at getting visibility (almost) anywhere in the
| entire system, it allows dynamic reinstrumentation, can be made container
| aware, is faster than alternatives, and is (usually) safe to run as long as you
| can load it. Consider using BPF if any of the following apply to you:
|
| - You have the in-house resources and expertise to build and maintain a
| long-lived BPF telemetry source.
|
| - You only want to use BPF for live debugging or other short-lived, one off, use
| cases such as bpftrace.
|
| - You're lucky enough to only have to support a single kernel version.
|
| - You don't really care if the project succeeds, you just want to get experience
| with BPF (this might legitimately apply in R&D orgs).
|
| If you don't have the resources and need to support a wide range of kernels,
| you might be better off looking for an alternative (there are many free and
| open source options thanks to GPL), or paying someone else to build it for you.
|
| Long running BPF programs for security are a relatively new use case. The
| tooling around this use case is getting better all the time, but there's still
| a lot to consider before diving in.
+-

+------[references]--------------------------------------------------------------------------+
|  [0]: [https://github.com/redcanaryco/oxidebpf]                                            |
|  [1]: Will go public Soon(TM) at                                                           |
|       [https://github.com/redcanaryco/linux-kernel-cloud-component-builder]                |
|  [2]: [https://github.com/redcanaryco/redcanary-ebpf-sensor]                               |
|  [4]: [https://lwn.net/Articles/870269/]                                                   |
|  [5]: [https://lwn.net/Articles/812503/]                                                   |
|  [6]: [https://elixir.bootlin.com/linux/latest/source/kernel/trace/bpf_trace.c#L646]       |
|  [7]: [https://www.brendangregg.com/bpf-performance-tools-book.html]                       |
|  [8]: [https://github.com/vbpf/ebpf-verifier]                                              |
|  [9]: [https://github.com/iovisor/bcc/issues]                                              |
| [10]: [https://en.wikipedia.org/wiki/0x10c]                                                |
| [11]: [https://lwn.net/Articles/752047/]                                                   |
| [12]: [https://github.com/redcanaryco/redcanary-ebpf-sensor/blob/main/src/programs.c#L393] |
| [13]: [https://github.com/brendangregg/FlameGraph/]                                        |
| [14]: [https://github.com/kdlucas/byte-unixbench]                                          |
| [15]: [https://linux.die.net/man/5/limits.conf]                                            |
| [16]: [https://github.com/aya-rs/aya]                                                      |
| [17]: [https://cve.mitre.org/cgi-bin/cvekey.cgi?keyword=BPF]                               |
| [18]: [https://elixir.bootlin.com/linux/latest/source/kernel/trace/trace_kprobe.c#L1568]   |
| [19]: [https://elixir.bootlin.com/linux/latest/source/kernel/trace/bpf_trace.c#L95]        |
+--------------------------------------------------------------------------------------------+
```
