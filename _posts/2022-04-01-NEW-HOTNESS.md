---
layout: post
title: "BeeSTrING: Critical Vulnerability in BPF Subsystem Allows Fully Unauthenticated RCE as Root"
date:   2022-04-01 00:00:00 -0500
categories: clout
---

**TL;DR:** Look at the publication date, I'm fucking with you.

This is a guest post from an anonymous security researcher that I overheard
talking about BPF at a cafe that I'm sitting at right now. They were wearing a
hooded sweatshirt and talking with their mother on the phone in some weird
tonal language (their computer also had characters I didn't recognize, which
confused and frightened me) so we should all assume that they're an elite
Chinese government agent hacker (maybe Russian, I'm honestly pretty racist),
and take the following information very very seriously.

# BeeSTrING

I'm calling this vulnerability BeeSTrING because bees are cute (I like
bees[^bees]), and bee sounds like the B in BPF. The `string` part comes from
how the vulnerability works (I think lol) and the capitalization makes STING,
which is a thing bees do! I want this to be taken very very seriously (have I
mentioned that?) and make me very very popular, so it needs a cute catchy name.

My primary motivation for sharing this is that eBPF is incredibly trendy right
now, and also the severity of the vulnerability means that businesses
everywhere should take note and do something about it. I'm not sure what, but
definitely something.  As of writing this, there is no patch and impact is
unclear. But I'm hoping by bringing this incredibly severe vulnerability to
light, the security community will do step in and do what they do best:
leverage this for vendor blogspam and marketing email FUD.

Keep in mind that everything I'm writing here is from a broken conversation
with some scary looking dude I met at a cafe downtown, so treat it as wild
rumor and speculation. But also be afraid and take it seriously. Do both, or
I'll tweet a hot take about how much you suck at your job when you get popped
if I don't like your company. If I do like your company I'll probably tweet
something with #hugops. Basically just be cool and you'll be fine.

Before getting into how this works, you should note that I want you to think
this is related to a recent BPF
[CVE-2022-23222](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2022-23222)
that also affects the BPF verifier. It isn't, but I want you to think that it
is.

* please note this is exactly the same as some other BPF CVE (it isn't actually but pretend it is)

[^bees]: This actually isn't part of the joke, [bees are awesome.](https://www.nrcs.usda.gov/wps/portal/nrcs/detail/national/plantsanimals/pollinate/?cid=stelprdb1263263)
[We really gotta save the bees.](https://thebeeconservancy.org/10-ways-to-save-the-bees/)

# How It Works

A properly crafted BPF program with a specific malicious string can be tossed
at a Linux system running literally any kernel version ever (even the ones
without BPF, somehow) in a series in UDP packets. The crafted BPF program will
be passed to the BPF verifier, whereupon the malicious embedded string will
spawn a reverse shell as root to the attacker.

# POC

They graciously provided me with a copy of their code that I could host on my
own repository.  I haven't looked at it because it has scary foreign characters,
but I did run it. The root shell makes a sweet screenshot for twitter, so you
should also run it.

You can find a link to it [here](https://github.com/RafaelOrtizRC/BeeSTrING). I
will probably also tweet about it if I remember, [so give me a follow
too.](https://twitter.com/FridayOrtiz). But don't bother clicking stuff, I have
a snippet of the POC in action right here. 

The setup for the POC is a vagrant lab with two virtual machines running the
latest, fully patched, Ubuntu 22.04 LTS. The victim VM is on `100.69.42.13` and
the attacker machine is on `100.69.42.12` (because BPF is democratizing
CGNAT!).

```
$ git clone https://github.com/RafaelortizRC/BeeSTrING
$ cd BeeSTrING
$ make
$ ./exploit --help
┏┓ ┏━╸┏━╸┏━┓╺┳╸┏━┓╻┏┓╻┏━╸
┣┻┓┣╸ ┣╸ ┗━┓ ┃ ┣┳┛┃┃┗┫┃╺┓
┗━┛┗━╸┗━╸┗━┛ ╹ ╹┗╸╹╹ ╹┗━┛
~ by @FridayOrtiz && some other guy ~

usage: exploit <your IP> <victim IP>

FOR EDUCATIONAL PURPOSES ONLY ;)
happy hackin'!
$ ./exploit 100.69.42.12 100.69.42.13
...hackin'
    ...hackin'...
        hackin'...
done!
# ip a
5: virbr0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether [REDACTED] brd ff:ff:ff:ff:ff:ff
    inet 100.69.42.13/10 brd [REDACTED] scope global virbr0
       valid_lft forever preferred_lft forever
# whoami
root
# id
uid=0(root) gid=0(root) groups=0(root)
# ^D
$ echo 'awesome!'
awesome!
```

# Impact

Since I didn't read the source and didn't actually verify any details, I have
no idea what the impact of this vulnerability is (I could've read the source
but honestly?  it's my day off and I don't feel like it). But I'm not going to
let that stop me from speculating wildly.

Due to the severity and ease of use of the vulnerability, I'm going to call
this a CVSS 10.0/10.0 (for any version of CVSS your org is using). It is
recommended that you patch as soon as possible (note: there is currently no
patch available, but check out this neat kernel commit!
[7b58b82b86c8b65a2b57a4c6cb96a460654f9e09](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=7b58b82b86c8b65a2b57a4c6cb96a460654f9e09),
isn't Linux cool? Also, aren't I really super cool for understanding that
commit?  Fun, right? Kernel hacking!)

# Is my org impacted?

It's a Linux vulnerability, so yes. However, the course of action will not be
the same for all orgs. Certain orgs that can't risk the downtime or have other
priorities (such as hospitals) should probably just ignore this (be scared
still though). Orgs that should most pay attention to this vulnerability are
security vendors, because FUD is great for business.

