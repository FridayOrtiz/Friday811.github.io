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

### Running the Live Patcher

### Perusing the eBPF Bytecode

### Finding the Vulnerability

### Exploiting the Vulnerability