---
layout: post
title: "Who turned all this shit on? A Kernel Hardening Guide"
date: 2026-05-08 15:00:00 -0400
categories: linux
tags: [linux, kernel, curmudgeon]
---

**tl;dr**: I asked the nice robot to help me build a repo that categorizes kernel
config options by risk and legitimate users, creating a hardening guide for
things you should probably just disable.

**'tl;dr'tl;dr**: turn off the ham radio modules, please.

Hardening Kconfig [here](https://github.com/FridayOrtiz/turn-that-shit-off/blob/main/hardening/hardening.kconfig).
Hardening module blocklist [here](https://github.com/FridayOrtiz/turn-that-shit-off/blob/main/hardening/hardening.conf).

## A Disturbing Morning

I awoke this morning to something terrible: a message from a friend containing
only the link to the DirtyFrag repo, adorned with several fire and explosion
emoji reactions. Thanks, chat. 

At this point I am still in bed, trying to get my 90 pound golden retriever off
my chest so I can read this repo on a properly sized screen.

This is the second LPE to drop this week, from a researcher using AI.  Good
thing I'm also a researcher, but I'm specialized in Linux, not AI! Thankfully,
the Claude app supports Apple Pay, so it was very easy for me to (tactically)
purchase a license in response.

At this point I am waiting for my espresso machine to warm up.

Before talking to the robot, I had a human thought: why are all these ancient
modules nobody uses still enabled by default on a wide range of distros?  Like,
yeah, the STIGs say to turn them off, but who reads those? So I used my human
brain to ask the robot to help me look through the kernel git history and find
high risk modules and features that nobody really needs or uses. 

N.B.: One thing that AI is really great at is reducing the cost of exploring any
ridiculous research hypothesis that slides across my brain.  It hasn't done much
for the cost of reviewing them, sadly.  Which is why I'm typing this with my
human hands instead of letting the nice robot write it for me.

One common theme between [CopyFail](https://github.com/theori-io/copy-fail-CVE-2026-31431) and [DirtyFrag](https://github.com/V4bel/dirtyfrag) was the exploitation of
relatively exotic kernel subsystems that are autoloadable, enabled by default
across many distros, and barely used anymore (when was the last time YOU used
AF_ALG to interact with the kernel crypto API from userspace?? I thought so
(orangesite readers need not reply)). I set those three criteria as my starting
point. Hey Claude, how can we programmatically identify these low value, high
risk, code paths, and build a kernel hardening guide that mitigates them for
most people, without hurting users that legitimately rely on them?

At this point, the coffee has done its thing and I am getting ready to go for a
morning run.

Claude flombulated for a bit and, thousands of tokens later, produced [this
repository](https://github.com/FridayOrtiz/turn-that-shit-off) that did exactly that. I want to make a joke about how it took a lot
of work to go back and forth and refine the criteria until we got something I
liked but it honestly only took a few iterations. Most of the work of churning
through the kernel git history happened while I on my morning 10k. I find cardio
helps me stay centered when we receive panicked calls from customers about the
latest exploit drops.

At this point I smell terrible, and am working on getting DirtyFrag coverage out
our customers at $dayJob. Claude churns on.

If you want to see the repo it's here: [github.com/FridayOrtiz/turn-that-shit-off](https://github.com/FridayOrtiz/turn-that-shit-off). I also linked it above, you should
really click more things. It's easy and free.

The repo has some specific hardening configurations, and I'll summarize some of
the top findings at the end of this post. If you're more journey-oriented than a
destination-girly, keep reading. If you're just trynna Get There, skip to the
end or go to the repo. Or have Claude read it for you.[^job]

[^job]: Oh my god, I'm going to have a job forever.

## Great Artists Steal

I needed to set some criteria to start our search for useless subsystems and
risky features. Instead of deriving this from first principles, I just ripped
off CopyFail and DirtyFrag. What would we have needed to do to, a priori, have
flagged these subsystems for default-disablement?

I started the search just by parsing MAINTAINERS files, but that wasn't super
useful. Just parsing maintainers gives a rosy view of subsystems that is not
reflected in reality. Just because loads of people maintain filesystem support,
doesn't mean AFS is a modern filesystem with lots of users. Then I tried
dividing maintainers by specific Kconfig options. This was better, but still not
granular enough to yield the specific CopyFail and DirtyFrag modules. So I
divided that even further, by actual code modules. This got us to something I
think is workable.

Here's how Claude interpreted my criteria when implementing:

1. **Ancient code.** Both subsystems predate 2010. Old code is a
   problem not because old code is worse, but because the people who
   wrote it have moved on and nobody else really knows it.
2. **Autoloadable from unprivileged context.** Either a `MODULE_ALIAS`
   on a socket family, or a filesystem registration that fires on
   `mount`, or a USB ID that fires on hotplug. Some unprivileged
   action triggers a kernel module load.
3. **Default-on in distro kernels.** Doesn't matter what the upstream
   `defconfig` says. What matters is what `/boot/config-$(uname -r)`
   looks like. Distros are conservative about turning things off.
4. **Ghost-maintained.** Few commits in the last 5 years, fewer
   distinct authors, and a high fraction of those commits are
   bandage-fixes (subjects matching `/fix|leak|race|uaf|oops/`).
   This is the "MAINTAINERS file says someone owns it but the git log
   says nobody actually does" pattern.
5. **Touches the paged-skb / page-cache fast paths.** `skb_frag_*`,
   `MSG_SPLICE_PAGES`, `sendpage_ok`, `copy_page_to_iter`,
   `splice_to_pipe`. This is the surface DirtyFrag's chain rode
   between the two halves.


This turned into five tuneable threshold flags. It's a lot to read, so if you
want to just run it, here you go.

```
python3 summary_stats.py --out copyfail-class.md --label "CopyFail-class candidates" \
    --min-paged-skb-files 0
python3 summary_stats.py --out quiet-orphans.md --label "Truly quiet orphans" \
    --max-authors-5y 10 --drop-supported
```

1. `--max-first-year` (default 2010):  Only includes sections where the first
   commit touching any matched file is in year ≤ N. Controls the "ancient code"
   axis. The intuition: code from before ~2010 predates the era when kernel
   security got serious attention (KASAN, Smatch, syzkaller all came later) and the
   original authors have mostly moved on. The default 2010 brackets the AF_ALG/algif_aead
   family (CopyFail; AF_ALG core landed in 2.6.38 / March 2011, algif_aead
   specifically went in around 2014) and rxrpc/esp4/esp6 (DirtyFrag, all 2005–2007). Lift to 2014
   or 2016 to catch newer code that's already aging. Note that first_year is
   bounded by 2005-04 (start of git-managed kernel history) — anything =2005
   actually means "older than git history" and the cutoff treats them all the same.

2. `--max-authors-5y` (default 40): Only includes sections with strictly fewer
   than N distinct commit authors in the last five years. Controls the
   "ghost-maintained" axis — fewer authors means less developer attention, fewer
   eyes on the code, less chance someone notices a bug class before an attacker
   does. The default 40 is generous enough to keep small-but-niche subsystems while
   excluding the mega-sections that dominate by scale alone (BLOCK LAYER has 459,
   NETWORKING [GENERAL] has 1547). Tighten to 10 or 15 to surface true orphans;
   loosen to 100 to catch large-but-net-neglected sections (NETWORKING [IPSEC] has
   147 5y-authors and DirtyFrag still happened — the section default 40 excludes
   it, which is a known section-grain limitation; the per-symbol pass in
   kconfig_score.py is the fix for that case).

3. `--min-autoload-files` (default 1):  Sections must have at least N source
   files containing an autoload pattern. The patterns are in collect_signals.py:
   sock_register, proto_register, genl_register_family, register_filesystem,
   MODULE_ALIAS_NETPROTO, MODULE_ALIAS_FS, request_module, xfrm_register_*, plus a
   handful more. Controls the "door is open" axis — the difference between a bug
   that requires already-elevated privilege to reach and one that any unprivileged
   process can ping into existence with a socket() call or a mount() syscall.
   Setting --min-autoload-files=0 disables the filter and includes code that's
   risky on the other axes but only reachable through some prior step.

4. `--min-paged-skb-files` (default 1):  Sections must have at least N source
   files matching one of the paged-skb / page-cache patterns: skb_frag_*,
   MSG_SPLICE_PAGES, sendpage_ok, copy_page_to_iter, copy_page_from_iter,
   splice_to_pipe, vm_insert_page, etc. This is the surface DirtyFrag's two halves
   chained through, and the most exploit-class-specific axis on the score list.
   This is the flag most likely to need retuning per exploit class. CopyFail itself
   doesn't ride this surface — algif_aead is in the crypto side path, not the
   page-cache fast path — so the current 1 default actually excludes the CopyFail
   family at section grain. Set --min-paged-skb-files=0 if the next class you're
   hunting isn't splice/sendpage-shaped, and use the autoload axis alone.

5. `--drop-supported` (default off): Strips sections whose status string
   contains Supported. By default they're included. The score.py formula already
   weights Supported low (only +0.5 vs Orphan at +4.0), so on score they bubble
   down on their own. But the profile-shape filter doesn't go through score — it's
   pure threshold logic — and Supported sections can still match the autoload +
   paged-skb + age + low-author profile. AF_RXRPC is Supported and DirtyFrag still
   happened. Use this flag if you want to focus on the truly-no-one-cares cases and
   accept that you're missing nominally-supported-but-actually-neglected code.

These defaults are SUPER CopyFail/DirtyFrag specific, so you may want to play
with the criteria locally. Note that this is also relying on plain ol' grepping
the git history. CodeQL, semgrep, whatever fancy code exploration tools for high
risk paths, if fully out of scope for this. It's not about finding exploitable
old modules, it's about turning off the shit that has terrible vibes.

Anyway, you can see the exact score weights in `score.py` and
`kconfig_score.py`.  There was no hyperparameter tuning here, to be clear. It
was just running numbers on vibes until CopyFail and DirtyFrag shook out.

## Materials y Methods sin Materials

Here's the actual process we went through to get here, according to Claude
itself. Cleaned up for coherence.

1. Phase 1+2: per-MAINTAINERS-section score. `score.py` adds up the
   axes listed at the top — ancient code, autoload signals,
   paged-skb signals, low-activity, high-fix-ratio, CVE history,
   default-y, in-defconfig — minus a maintainer penalty (M: lines)
   and a crowd penalty for sections with 300+ recent authors. Cap
   is around 16, anything above 8 is a strong candidate.

2. Phase 2.5: per-Kconfig-symbol score. This is where it gets
   interesting. `kconfig_index.py` parses every `Kconfig` file in
   the tree. `build_select_graph.py` builds the cross-symbol
   `select` graph; the in-degree of a symbol tells you how many
   other corners of the kernel will break their Kconfig if you turn
   it off. Symbols with in-degree zero are "structurally niche" —
   nothing else depends on them. Combine with distro coverage (the
   four distro configs in `distros/`), per-symbol surface
   enrichment (Makefile parse + global grep intersection),
   inherited section signals, crowd-penalty downweighted ×0.25
   when the symbol has ≤5 attributed source files.

3. Triage: false positives in the structurally-niche set. There are a lot.
   `TUN`, `VETH`, `VXLAN`, `GENEVE`, `MACVLAN` — every container
   runtime. `PACKET` — tcpdump, Wireshark, eBPF. `BLK_DEV_LOOP`,
   `BLK_DEV_RAM` — squashfs, qemu-nbd. `IPV6` (yes, it scores
   high; no, you do not disable IPv6 in 2026). The select-graph
   in-degree is a measure of _Kconfig dependency_, not _runtime
   use_. Manual triage from the structurally-niche set is what
   produced the curated list above. The audit ships the structural
   shortlist; this post ships the post-triage list.

4. Limits and known holes. MAINTAINERS-section grain is too coarse
   for things like `AF_ALG/algif_aead` inside the CRYPTO API; the
   per-symbol pass is a partial fix but Makefile attribution is
   best-effort. F: glob expansion is best-effort. The 5-year
   activity window is a snapshot. CentOS Stream and Amazon Linux
   2023 aren't in the distro matrix yet. Etc.

If you're paying attention you'll notice the downside here: it can't actually
produce an authoritative result. Too many false positives. A human still needs
to triage the output to remove stuff that probably shouldn't be disabled. Or you
could, like, just ask Claude to do it. You have Claude right? It's really easy
to get Claude. They take Apple Pay.


## Who put all this code inside me?

Here's the top offenders of code that's probably _inside your kernel right now_
that you'll never use! It's just sitting there, _waiting to pwn you!_ Cool,
right?

### legacy network protocols

Apologies to my amateur radio friends but your hobby makes my job harder.

* `AppleTalk`, `AX25`/`NETROM`/`ROSE` (amateur radio), `LLC2`,
`AF_KCM`, `TIPC`, `PHONET`, `IEEE802154` (Zigbee/6LoWPAN), `MISDN` (modular
ISDN), `CAIF`, `RDS`.

None of them have any business being default-loadable on a 2026 desktop or
server.  If you're a ham radio user, running on Linux, you're probably smart
enough to turn these on manually. If you're not a ham radio user, why is your
kernel set up to accept incoming AX.25 packets?

Special shoutout to TIPC 0days, all my homies love TIPC 0days.

Also! `AF_RXRPC` — DirtyFrag's other half — gets an honorable mention.
This is the transport for AFS, which is a distributed filesystem
mostly used at universities and Big Old Companies. Disable unless
you mount AFS, which you would know if you did.

### legacy filesystems

Subtitle: Are you seriously running HPFS? Why? You can throw that OS/2 Warp
box away. It's not coming back.

* `AFFS` (Amiga), `JFS` (IBM AIX/OS/2), `JFFS2` (embedded flash),
`HPFS` (OS/2), `EFS` (SGI), `QNX4`/`QNX6`, plus a long tail of
`OMFS`, `BFS`, `BEFS`, `ADFS`, etc. All autoload via the mount-time
fstype lookup, which means a malicious USB stick with a forged JFS
superblock can pull `jfs.ko` into your kernel from kernel context
before you've even finished plugging it in. This is on the same
register as the FAT autoloading vulnerabilities of the late 2010s
and roughly nobody is paying attention to JFS.

`eCryptfs` is a special case, because Eric Biggers has [announced its removal in
Linux
7.0](https://www.webpronews.com/linux-7-0-will-finally-pull-the-plug-on-ecryptfs-the-end-of-a-filesystem-encryption-era/).
The kernel maintainers want it gone. It's been deprecated for over a decade. Use
fscrypt or LUKS. Caveat: anyone who installed Ubuntu earlier than 18.04 with
the encrypted-home option still has it active (for those of you who have been
diligently upgrading your personal box for 8 years). If you `ls /home/.ecryptfs`
and get something back, you need to migrate to LUKS before turning eCryptfs off,
or you will not be able to log in. This is the kind of "test first" failure mode
that sounds dramatic until you remember Ubuntu 24.04 ships `CONFIG_ECRYPT_FS=y`,
_built into the kernel_, so the modprobe blocklist won't even take effect. You'd
need to recompile your kernel, a thing everyone does in 2026.

There's also `HFS` and `HFSPLUS`, which are how you mount older Mac-formatted
external drives on Linux. I'm filing this one under "if you need it you probably
know."

### PPTP and friends

`PPTP` is cryptographically broken
[since 2012](https://moxie.org/2012/07/30/defcon-talks.html), is
deprecated in NetworkManager, was dropped by every major commercial
VPN provider in 2024, and Microsoft formally deprecated it in October
2024. It's still =m on every distro I checked. `PPP_MPPE` (Microsoft
Point-to-Point Encryption) is its sidekick, only ever used by PPTP,
RC4 + MS-CHAPv2, see above re: cryptographically broken since 2012.

`IPV6_SIT` is for 6to4 (deprecated by RFC 7526 in 2015) _and_ for 6in4
(Hurricane Electric tunnels, etc.). If you have an HE.net tunnel, keep
this. Most people don't.

### break bluetooth harder

`BT_RFCOMM`, `BT_HIDP`, `BT_BNEP`, `BT_CMTP`. These autoload on
`socket(AF_BLUETOOTH, …, BTPROTO_X)`. The whole BT stack stays in the hardening
config, this is just the per-profile sockets. 

The exact ones you disable depend on how much bluetooth you need in your life.

- RFCOMM: BT audio headset control channels (HFP, AVRCP) ride this.
  A2DP audio itself goes over L2CAP, but the control channels that
  every smart headset negotiates over go through RFCOMM. So if you
  have a BT headset, you keep RFCOMM.
- HIDP: BT keyboards and mice fail to pair without it.
- BNEP: BT-PAN tethering. You probably don't need this.
- CMTP: ISDN over Bluetooth. What even is this.

If you have a Bluetooth radio in your laptop and you don't use it,
disable the whole stack with `install bluetooth /bin/false`. If you
do, this is the place to be careful.

### you should really know if you're running xen

If `systemd-detect-virt` says anything other than `xen`, the entire Xen stack,
front-end drivers, back-end drivers, `xenfs`, `xen-acpi-processor`, all of it,
is dead weight. The Xen HYPERVISOR INTERFACE section has 16 CVEs in 10 years,
which is fine if you're a Xen user (you're paying for the privilege), and not
fine if you're not. Ten or so symbols turn off as a unit.

### orphan hardware drivers

Pre-802.11g wireless (`ADM8211`, `B43LEGACY`, `CW1200`,
`LIBERTAS_SPI`, `WL1251_SPI`). PCI Ethernet from before the iPhone
(`8139CP`, `VORTEX`, `TYPHOON`, `VIA_RHINE`, `HAPPYMEAL`, `SUNGEM`,
`ADAPTEC_STARFIRE`). USB DVB tuners and old V4L2 capture cards
(`SAA7134`, `CX88`, `PWC`, the entire `DVB_USB_*` family). PCMCIA.
The floppy driver. Software FCoE that Red Hat deprecated in
RHEL 7.4. A couple dozen modules in this bucket.

Seriously. Why does my development server default to supporting Original XBox
DVDs?

### NFC

The whole `NFC` subsystem is `Orphan` upstream and only useful if
you have an NFC reader USB stick or the kind of phone-class device
that has one built in.

## Well, you see, it depends...

There's a bunch of stuff in the grey middle zone between "stuff nobody really
uses" and "stuff everybody uses" that I'd like to call "stuff a good amount of
people use and for the stuff they use it for it's pretty important but for most
people it's probably not necessary or important but these things are common
enough that you may not realize you rely on them so really do be careful."

The IPsec block (`INET_AH`, `INET_ESP`, `XFRM_USER`, `NET_KEY`, the v6 mirrors)
is the exact surface DirtyFrag rode through. If you run strongSwan or libreswan
or NetworkManager-strongswan, leave it. If you don't, disable it. Same logic for
L2TP (`L2TP`, `L2TP_IP`, `L2TP_ETH`). `vhost_net`/`vhost_scsi`/`vhost_vsock` are
the virtio host backends — every KVM user needs them, nobody else does.
`BINFMT_MISC` is how Wine, qemu-user, and Docker buildx multi-arch hook into the
binary loader.

Then there's the application-layer NAT helpers: `NF_CONNTRACK_FTP`,
`NF_CONNTRACK_SIP`, `NF_CONNTRACK_H323`, etc. These are the protocol-aware ALG
translators that home routers used to need to make active-mode FTP and SIP/VoIP
traverse NAT. Most modern setups don't, and `nf_conntrack_sip` specifically
picked up CVE-2026-31427 and CVE-2026-23457 in the same audit cycle. If your
firewall isn't doing protocol-aware NAT for these, kill them.

CephFS is no longer just for cluster admins! Proxmox mounts it by default,
Rook-managed Kubernetes nodes use it, microceph put a cluster in your laptop. So
`mount -t ceph` before disabling.

The full conditional list is in [`hardening.conf`][^conf] under the
`CHECK FIRST` headers. Each block has the exact one-liner you can
run to determine if you're safe to disable.

## I said Great Artists Steal already, right?

Remember how AI makes it really easy to slap out a hypothesis without much
thinking? Well, while the robot scrobbled away, I wanted to consider prior art.
There's a lot of similar work out there, but they're all generally a bit more
conservative and a bit less reproducible.

[ANSSI
BP-028](https://cyber.gouv.fr/sites/default/files/document/linux_configuration-en-v2.pdf),
the French national-cyber Linux configuration guide, has a recommended kernel
module blacklist that covers `dccp, sctp, rds, tipc, n-hdlc, ax25, netrom, x25,
rose, decnet, econet, af_802154, ipx, appletalk, psnap, p8023, p8022, can, atm`.
That's a _lot_ of overlap with my "legacy network protocols" cluster. ANSSI is
the closest existing list to what I'm doing on the network-protocol side; if you
want a more conservative starting point, ANSSI is it.

[CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/) for each major
distro cover the same network-protocol bundle plus the core legacy filesystems
(`cramfs`, `freevxfs`, `hfs`, `hfsplus`, `jffs2`). DISA STIG covers a subset of
CIS. Both are flat lists in compliance documents that don't show their work.

[Kicksecure's `security-misc`](https://github.com/Kicksecure/security-misc) is
the single closest existing project in spirit. They ship a Debian package with a
`/etc/modprobe.d/` blocklist that's even more aggressive than mine in a couple
of places (they unconditionally disable FireWire and Bluetooth; I treat both as
conditional). If you run Whonix or Kicksecure, you have most of this already.

[KSPP recommended settings](https://kspp.github.io/Recommended_Settings.html)
and the
[`kernel-hardening-checker`](https://github.com/a13xp0p0v/kernel-hardening-checker)
that audits against them are the canonical references for built-in kernel
hardening (KASLR, fortify-source, lockdown, the `INIT_ON_*_DEFAULT_ON` set).
They are _not_ about disabling subsystems — KSPP only flags `BINFMT_MISC`,
`INET_DIAG`, `LEGACY_PTYS`, and a few others.

So what did I get this silly little guy to actually build here that's novel?
Well, let's ask it!  Hey Claude, what's new?

1. **The pipeline is reproducible.** ANSSI/CIS/STIG/Kicksecure all
   publish lists. None of them publish how they decided what goes on
   the list. This audit's `score.py` and `kconfig_score.py` are
   public, the data files are public, you can re-run it against a
   newer kernel or a different distro mix. Lists go stale; pipelines
   don't.
2. **Conditional / workload-aware disables.** No existing guide
   handles "if you're not on Xen, disable the whole Xen stack" or
   "if you don't run KVM, disable vhost". Compliance lists pretend
   everyone needs everything that's load-bearing in some workload.
   I think the conditional pattern is right and I'm somewhat
   surprised nobody has packaged it before.
3. **The hardware-driver long tail.** Old NICs, old wireless, DVB
   capture cards, NFC. Not in any existing compliance list. Some are
   in Kicksecure.
4. **The recency angle.** ANSSI's last update was October 2022. CIS
   for the major distros lags about a year behind kernel releases.
   None of those guides reflect post-2024 events: CopyFail,
   DirtyFrag, the eCryptfs removal patch, the Microsoft PPTP
   deprecation. The score-driven pipeline ranks the new candidates
   on the same axes as the old ones, so the new ones (`AF_KCM`,
   `PHONET`, the DVB family) just fall out automatically.
5. **The per-symbol scoring step.** This is the geeky one. The audit
   ranks at MAINTAINERS-section grain first, but big sections like
   "CRYPTO API" then dilute the signal — `algif_aead` (CopyFail's
   exact symbol) inherits noise from the entire crypto API, and
   gets buried at section-grain rank ~3700. The per-symbol pass
   parses Makefiles to attribute source files to specific
   `CONFIG_X` symbols, intersects with the autoload/paged-skb hit
   sets, and re-ranks. After the rerank, `CRYPTO_USER_API_AEAD`
   moves to ~280, `INET_ESP`/`INET6_ESP` to top 15, `AF_RXRPC` to
   ~320. This is where the post earns its keep, methodology-wise.

There's also academic work — Kurmus et al.'s NDSS 2017 paper on attack-surface
metrics, the ktrim work out of TU Braunschweig — and this audit's per-symbol
score is in the same category. It would be silly to pretend academic precedent
doesn't exist; the score formula itself is bespoke.  The contribution here,
I suppose, is "functioning operator-facing pipeline that catches what the
compliance lists are 2-4 years behind on."

## I want to harden my laptop, but not so hard it becomes a brick, can you help?

The deliverables are in [the audit repo](https://github.com/FridayOrtiz/turn-that-shit-off):

- `hardening.conf` — drop into `/etc/modprobe.d/`, rebuild
  initramfs (`update-initramfs -u`, `dracut -f`, or `mkinitcpio -P`,
  per your distro), reboot.
- `hardening.kconfig` — `CONFIG_X=n` fragment for custom kernel
  builds. Apply with `merge_config.sh`.
- `verify.sh` — audit-your-own-box script. With `--probe` it tries
  `socket(AF_X, …)` for each blocked AF and reports which ones
  loaded anyway.

The thing I want to make a big deal of, and the reason this is the
last section before the methodology, is **don't apply this in prod
without testing it**. The blocklist will break, at minimum:

- Anyone on an IPsec VPN.
- Anyone on an L2TP VPN.
- Every KVM host (vhost).
- Every Wine / qemu-user / Docker buildx multi-arch user (binfmt_misc).
- Bluetooth audio headsets (RFCOMM control channels).
- Bluetooth keyboards and mice (HIDP).
- Anyone on Ubuntu pre-18.04 with encrypted home (eCryptfs).
- Anyone with a Hurricane Electric IPv6 tunnel (sit).
- CephFS / OCFS2 / GFS2 users.
- Anyone serving iSCSI (LIO).
- Hams. Don't break things for hams. Hams are nice. Greetz 2 Waggons.

The good news is that if you DO break something, it should be pretty obvious.
Just go find what broke and turn it back on. Perhaps apologetically, if you're
on a shared system.

## False Positives

There are always so many. Ugh. There's some stuff not on the hardening guide
that do get flagged as suspicious, but are really common and do have Good Vibes.
`TUN` (every VPN), `VETH` (every container), `VXLAN`/`GENEVE`/`MACVLAN`/`IPVLAN`
(every overlay network), `PACKET` (tcpdump, Wireshark, every kernel-bypass
thing), `BLK_DEV_LOOP` (snap, flatpak, squashfs), `BLK_DEV_RAM` (initramfs),
`IPV6`, `CFG80211` (Wi-Fi), `CONNECTOR` (proc events for audit, lxc),
`ACPI_PROCESSOR` (every modern x86), `BINFMT_MISC`-but-tier-2, the `IP_NF_*` and
`NETFILTER_XT_*` family (Docker still uses iptables-legacy by default),
`BTRFS_FS`, `SOUND`.

These are all "structurally niche" in the Kconfig sense: nothing else in the
tree `select`s them. But people, you know, actually use them to do work. The
audit picks them up because the audit looks at the kernel source, not at what
you run on your kernel after it's built.

## Stuff Claude wanted to make sure I told you

In no particular order...

- Audit kernel rev: `af4e9ef3d784` (master @ 2026-03-02). Ingested
  distro configs are from 2026-05-08: Arch, Debian-latest, Fedora
  Rawhide, Ubuntu 24.04 LTS.
- Numbers will drift across kernel releases. If you're hardening a
  long-lived appliance/kiosk/embedded board, re-run the audit at
  rebase.
- Static analysis only. This complements (does not replace)
  syzkaller, KASAN, and the ongoing CNA disclosure stream.
- I have not coordinated this with kernel.org maintainers or with
  any distro security team. Treat as an operator's harm-reduction
  guide, not a kernel-policy proposal.

I don't know why it felt the need to caveat that this is not a kernel policy
proposal.  Like, obviously? Welp. See ya later!

[conf]: https://github.com/FridayOrtiz/turn-that-shit-off/blob/main/hardening/hardening.conf
