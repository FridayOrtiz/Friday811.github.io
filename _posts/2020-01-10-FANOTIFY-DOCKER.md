---
layout: post
title:  "Using fanotify within Docker Containers"
date:   2020-01-10 19:00:00 -0500
categories: linux
tags: [linux, docker, fanotify]
---

I was recently dockerizing tests for a program I'm working on that utilizes
[fanotify](http://man7.org/linux/man-pages/man7/fanotify.7.html) and noticed
that the tests, which worked in a VM, were failing to run. Reviewing the logs
yielded the culprit: `fanotify_init` could not be called in the container. TL;DR:
you need to run the container with the `CAP_SYS_ADMIN` capability. But I'm 
new to the Linux kernel and wanted to know why this was necessary.

To replicate the issue at home, use the following dockerfile:

```Docker
FROM ubuntu:19.10

WORKDIR /fanotify
COPY . /fanotify
RUN apt-get update
RUN apt-get install -y build-essential
RUN gcc fanotify_example.c -o fanotify_example
CMD ["/fanotify/fanotify_example", "/fanotify"]

```

The file `fanotify_example.c` is copy-pasted from the first example on the
[man page](http://man7.org/linux/man-pages/man7/fanotify.7.html). 
Building the container should work, but running yields an error:

```sh
user@linux:~/fanotify$ docker build -t test_container .
...
user@linux:~/fanotify$ docker run --rm test_container
fanotify_init: Operation not permitted
Press enter key to terminate.
```

## Docker and seccomp

I found [this issue](https://github.com/docker/for-linux/issues/496) on the
Docker github page. It refers to issues running Chrome in a container without
disabling the sandbox security feature or giving the container `CAP_SYS_ADMIN`.
This is not ideal, as it disables some of docker's security 
features. Later down in the thread someone shows it working
with a custom `seccomp` profile, but before I got to that I needed to know
what `seccomp` was.

From reading the [docker docs](https://docs.docker.com/engine/security/seccomp/)
and [wikipedia page](https://en.wikipedia.org/wiki/Seccomp) I was able to infer
that seccomp is used to restrict the syscalls available to a given process. This
made sense, the default security profile was restricting the container's access
to the `fanotify_init` syscall. I checked if `seccomp` was enabled in my kernel
and it was:

```sh
user@linux:~/fanotify$ grep CONFIG_SECCOMP= /boot/config-$(uname -r)
CONFIG_SECCOMP=y
```

I guess I really should have read the manual first.

The Github issue thread mentions that the Chrome docker 
[`seccomp` profile](https://raw.githubusercontent.com/jfrazelle/dotfiles/master/etc/docker/seccomp/chrome.json)
whitelists several syscalls not found in the default profile, including the 
one I need: `fanotify_init`.
So if we copy that profile and use it to run the container it should work, right?
I wanted to be a little smarter than that, so I found the 
[default docker profile](https://github.com/moby/moby/blob/master/profiles/seccomp/default.json)
and attempted to modify it by moving `fanotify_init` to the whitelist.
Interestingly, `fanotify_mark` was already whitelisted by default.

First, download the profile:
```sh
user@linux:~/fanotify$ wget https://raw.githubusercontent.com/moby/moby/master/profiles/seccomp/default.json
```

Then remove `fanotify_init` from line 571 and add it after `fanotify_mark` on
line 95. The block surrounding line 571 already hints at what's going on here:
the list that `fanotify_init` is in is added when you add the `CAP_SYS_ADMIN`
capability to the container.

If you run the container again with this new profile you can see that...

```sh
user@linux:~/fanotify$ docker run --rm \
                                  --security-opt seccomp=default.json \
                                  test_container
fanotify_init: Operation not permitted
Press enter key to terminate.
```

...it still doesn't work.

## Calling fanotify_init

In fact, not only does adding `fanotify_init` to the whitelist not work, 
simply whitelisting everything with the `unconfined` option doesn't work
either:

```sh
user@linux:~/fanotify$ docker run --rm \
                                  --security-opt seccomp=unconfined \
                                  test_container
fanotify_init: Operation not permitted
Press enter key to terminate.
```

The only thing that works is giving the container `CAP_SYS_ADMIN`:

```sh
user@linux:~/fanotify$ docker run --rm --cap-add=CAP_SYS_ADMIN test_container
Press enter key to terminate.
Listening for events.
Listening for events stopped.
```

## Why?

So why is this happening? I noticed that nowhere in the example code does it
return a permission error. The error seemed to come from the code itself,
specifically the `perror("fanotify_init");` line, so I wanted to see what was
actually failing. The first place I looked was where the 
[`fanotify_init` syscall was defined](https://github.com/torvalds/linux/blob/master/fs/notify/fanotify/fanotify_user.c#L766) 
and to my surprise there was the answer on line 776:

```c
/* fanotify syscalls */
SYSCALL_DEFINE2(fanotify_init, unsigned int, flags, unsigned int, event_f_flags)
{
    // ...
	if (!capable(CAP_SYS_ADMIN))
		return -EPERM;
    // ...
}
```

If the calling process is not running with `CAP_SYS_ADMIN` capabilities then
`fanotify_init` itself refuses to run, returning insufficient permissions 
instead. Unfortunately, it seems that the only way to make `fanotify` work 
inside a docker container is to pass the container `CAP_SYS_ADMIN`.

This made me uncomfortable so I looked up the history of `CAP_SYS_ADMIN`. It
turns out I'm not the only one who thinks this is overly permissive. According to 
[this LWN article from 2012](https://lwn.net/Articles/486306/)
the `CAP_SYS_ADMIN` capability accounted for 30% of the uses of capabilities
at the time.
Having one capability responsible for so many calls seems, to my amateur eyes
at least, to defeat the purpose of the capability. The
[`capabilities` man page](http://man7.org/linux/man-pages/man7/capabilities.7.html) 
even warns against using `CAP_SYS_ADMIN` for new features:

```
       *  Don't choose CAP_SYS_ADMIN if you can possibly avoid it!  A vast
          proportion of existing capability checks are associated with this
          capability (see the partial list above).  It can plausibly be
          called "the new root", since on the one hand, it confers a wide
          range of powers, and on the other hand, its broad scope means that
          this is the capability that is required by many privileged
          programs.  Don't make the problem worse.  The only new features
          that should be associated with CAP_SYS_ADMIN are ones that closely
          match existing uses in that silo.
```

It's not ideal, but it looks like I don't really have a choice. Oh well,
at least I learned something.