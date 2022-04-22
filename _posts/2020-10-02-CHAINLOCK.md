---
layout: post
title: "ChainLock, A Linux Tool for Locking Down Important Files"
date:   2020-10-02 00:00:00 -0500
categories: linux
tags: [linux, security]
---

**This post was originally written for the ElevenPaths Innovation and
Laboratory website, and is available
[here](https://business.blogthinkbig.com/chainlock-linux-tool-locking-down-important-files/).**

Let’s say you have a valuable file on your computer, such as a bitcoin wallet
file (`wallet.dat`), or some other file with sensitive information, and you
decide put a password on it to keep it safe. If you use MS Windows maybe you’ve
taken steps to protect yourself from [clipboard hijacking
malware](https://ccw.e-paths.com/), and now you’re wondering what to do next in
the constant arms race against attackers.

We know about some malware that try to [target and steal your
wallet.dat](https://www.bleepingcomputer.com/news/security/racoon-malware-steals-your-data-from-nearly-60-apps/)
file so the attacker can crack your password offline and then transfer the
funds to an account they control, so from Innovation and Laboratory we wanted
to create something for Linux users.

We wanted the tool to be accessible, so it could be used to protect sensitive
files without doing things like recompiling the kernel or configuring SELinux.
We ended up with a new tool, dubbed
[ChainLock](https://chainlock.e-paths.com/?lan=en). ChainLock can lock any file
on your Linux computer such that it can only be opened by a specific
application.  For example, it can ensure your wallet.dat file can only be
accessed by your bitcoin core application and can’t be opened or copied by
malware.

## How does it work?

First, we onboard a file with the ChainLock command line program. This encrypts
the target file with a strong password, and then a QR code pops up on screen
which we can scan with the companion application for smartphones. Now the key
to unlock the protected file is only stored on your phone and can’t be found on
your computer. An attacker must compromise both devices to unlock your file
without permission.

That takes care of protecting the file at rest, but locked files aren’t very
helpful when you’re trying to use them. We can ask ChainLock to unlock the
file, and a QR code pops up. With the companion app we can select the file we
want to unlock, then scan the QR code. The app will send the information
necessary to unlock the file to your computer using a Tor hidden service.

ChainLock now starts a daemon to watch over the file and only allow access from
the authorized binary, and then decrypts the file so it can be used. Now the
wallet can only be used with the specified application. Nothing else works!
ChainLock also supports upgrading or changing the authorized program, so you
can always upgrade your wallet application without fear, or migrate to another
device.

## Where do I get it?

You can download ChainLock and the companion application at the [ChainLock
site](https://chainlock.e-paths.com/).  If you want a deeper look at how it
works, check out the accompanying
[walkthrough](https://chainlock.e-paths.com/walkthrough.html). The walkthrough
will guide you through installing and using ChainLock.

You can check this video to see Chainlock in action:

<iframe width="560" height="315" src="https://www.youtube.com/embed/CcxOeU0JpOM" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

With this tool we want to give to the community a new technique to ensure their
important files are kept safe. We hope you find it useful.
