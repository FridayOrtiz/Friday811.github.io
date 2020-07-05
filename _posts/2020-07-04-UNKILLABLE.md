---
layout: post
title:  "Creating an Unkillable Process by Abusing Character Devices"
date:   2020-07-04 22:00:00 -0400
categories: linux
---

TL;DR: This is probably a bad idea and you don't actually want use this.
Whatever problem you're trying to solve, [there's probably a better way.](https://meta.stackexchange.com/questions/66377/what-is-the-xy-problem/243965#243965)
I was researching ways to prevent a process from dying prematurely and
created a simple "device driver" that will prevent a given process from
being killed until the system is powered down or the process decides to end
on its own terms.

# Why create an unkillable process?

I was looking for ways to protect a process from being accidentally or
maliciously halted for a research project at work. Signal handlers did the
trick, but unfortunately [signal handlers can't handle `SIGKILL`:](https://man7.org/linux/man-pages/man2/signal.2.html)

>       The signals SIGKILL and SIGSTOP cannot be caught or ignored.

The section 7 entry for `signal` [basically says the same:](https://man7.org/linux/man-pages/man7/signal.7.html)

>       The signals SIGKILL and SIGSTOP cannot be caught, blocked, or
>       ignored.

In fact, this piece of advice [kept](https://stackoverflow.com/questions/2541597/how-to-gracefully-handle-the-sigkill-signal-in-java/2541618#2541618)
[popping](https://stackoverflow.com/a/15766845) [up](https://stackoverflow.com/a/3908710)
[everywhere](https://www.reddit.com/r/golang/comments/6a76pl/syscallkillpid_syscallsigkill_not_immediate/dhdhxv1).
The Internet seems to have taken the man page at face value as ultimate truth.
`SIGKILL` cannot be caught and it cannot be ignored. The signal is never sent
to the process, the kernel manages `SIGKILL` on its own, cleans up the process,
and the process is never heard from again. It simply vanishes!

Except that's not quite true. Process 1, `init`, will [ignore any terminating signals sent to it](https://unix.stackexchange.com/a/484452). 
That includes `SIGKILL`. `init` is a [userland process](https://stackoverflow.com/questions/23277706/does-linux-init-process-run-in-kernel-or-user-mode), 
so clearly this is possible. And that means _the Internet is wrong!_
I couldn't find a better source for `init` being immune to `SIGKILL` than
stackexchange, unfortunately. It doesn't appear to be well documented.
But if you're following along at home, go ahead and try it! It's perfectly
harmless. Send some `SIGKILL`s at your `init` process, pid 1.

```
$ sudo kill -9 1
$ ps aux | grep init
root           1  0.1  0.0 168580 12384 ?        Ss   17:11   0:12 /sbin/init splash
$ sudo kill -9 1
$ ps aux | grep init
root           1  0.1  0.0 168580 12384 ?        Ss   17:11   0:12 /sbin/init splash
$ Why won't you die?
> bash: unexpected EOF while looking for matching `''
```

Maybe it was out of morbid curiosity, or a desire to prove the Internet wrong,
but I wanted to create another user process which could not be killed.

# Creating an unkillable process.

So how do we prove the Internet wrong (for this very specific case)? Let's look
at what actually makes `init` unkillable. I'll spare you how I got here
and skip right the point. First, we have to define `task_struct`.
I recommend reading through the [kernel source](https://elixir.bootlin.com/linux/latest/source/include/linux/sched.h#L632),
it's not too complex. The gist is that [`task_struct` holds information about a process](https://stackoverflow.com/a/56538295)
for use by the kernel.

[Further down](https://elixir.bootlin.com/linux/latest/source/include/linux/sched.h#L925)
in `task_struct` we find a reference to a `signal_struct` called `*signal`:

```c
/* Signal handlers: */
struct signal_struct		*signal;
struct sighand_struct __rcu	*sighand;
```

The comment hints that the purpose of this structure is handling signals. If we
dig into [`signal_struct`'s definition](https://elixir.bootlin.com/linux/latest/source/include/linux/sched/signal.h#L82)
we see [this interesting line](https://elixir.bootlin.com/linux/latest/source/include/linux/sched/signal.h#L111):

```c
unsigned int		flags; /* see SIGNAL_* flags below */
```

Scroll down to [where signal flags are defined](https://elixir.bootlin.com/linux/latest/source/include/linux/sched/signal.h#L240) 
and we find [what we're looking for](https://elixir.bootlin.com/linux/latest/source/include/linux/sched/signal.h#L253):

```c
#define SIGNAL_UNKILLABLE	0x00000040 /* for init: ignore fatal signals */
```

A flag, for `init`, that marks the signal handler for this `init`'s `task_struct`
as "unkillable" and tells it to ignore fatal signals. Now we're getting 
somewhere! If we want to make an arbitrary process unkillable we simply
need to add the `SIGNAL_UNKILLABLE` flag to the process's `task_struct`'s
`signal_struct`.

The correct way to do this would be to add a new syscall that marks an
arbitrary process as unkillable with the flag. Unfortunately, adding a syscall
required [recompiling the kernel](https://medium.com/anubhav-shrimal/adding-a-hello-world-system-call-to-linux-kernel-dad32875872)
and I want to avoid doing that. This is already a bit of a hack, so why make
things harder. Luckily, we can get our kernel to run arbitrary code by
loading a new module. That only requires root privileges, no recompiling.

We will need a program we want to make immortal and a Linux Kernel Module that 
marks it as such. Let's start with the LKM.

First we'll take a boilerplate character device driver and use take advantage
of the `read()` function to communicate an arbitrary pid. Then we'll find
that pid's `task_struct` and assign the `signal_struct` the `SIGNAL_UNKILLABLE`
flag.

#### _unkillable.c_

```c
#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/types.h>
#include <linux/proc_fs.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/pid.h>

MODULE_LICENSE("GPL");

void unkillable_exit(void);
int unkillable_init(void);

/* device access functions */
ssize_t unkillable_write(struct file *filp, const char *buf, size_t count, loff_t *f_pos);
ssize_t unkillable_read(struct file *filp, char *buf, size_t count, loff_t *f_pos);
int unkillable_open(struct inode *inode, struct file *filp);
int unkillable_release(struct inode *inode, struct file *filp);
struct file_operations unkillable_fops = {
	.read = unkillable_read,
	.write = unkillable_write,
	.open = unkillable_open,
	.release = unkillable_release
};

/* Declaration of the init and exit functions */
module_init(unkillable_init);
module_exit(unkillable_exit);

int unkillable_major = 117;

int unkillable_init(void) 
{
	int result;

	result = register_chrdev(unkillable_major, "unkillable", &unkillable_fops);
	if (result < 0) {
		printk("Unkillable: cannot obtain major number %d\n", unkillable_major);
		return result;
	}

	printk("Inserting unkillable module\n"); 

	return 0;
}

void unkillable_exit(void) 
{
	unregister_chrdev(unkillable_major, "unkillable");
	printk("Removing unkillable module\n");
}

int unkillable_open(struct inode *inode, struct file *filp) 
{
	return 0;
}

int unkillable_release(struct inode *inode, struct file *filp) 
{
	return 0;
}

ssize_t unkillable_read(struct file *filp, char *buf, size_t count, loff_t *f_pos) 
{ 
	struct pid *pid_struct;
	struct task_struct *p;
	
	/* interpret count to read as target pid */
	printk("Unkillable: Got pid %d", (int) count);

	/* get the pid struct */
	pid_struct = find_get_pid((int) count);

	/* get the task_struct from the pid */
	p = pid_task(pid_struct, PIDTYPE_PID);

	/* add the flag */
	p->signal->flags = p->signal->flags | SIGNAL_UNKILLABLE;
	printk("Unkillable: pid %d marked as unkillable\n", (int) count);
	
	if (*f_pos == 0) { 
		*f_pos+=1; 
		return 1; 
	} else { 
		return 0; 
	}
}

ssize_t unkillable_write(struct file *filp, const char *buf, size_t count, loff_t *f_pos) 
{
	return 0;
}
```

The key part is the `unkillable_read()` function. This function is called when
we try to read from the device. The amount of bytes we are trying to read
is sent as the `count` parameter, which we abuse by reinterpreting as a pid.
With the pid in hand, we find the `task_struct` and `signal_struct` and mark
the process unkillable. The following makefile will build and install the
module.

#### _Makefile_

```makefile
obj-m += unkillable.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean

install:
	sudo insmod unkillable.ko

uninstall:
	sudo rmmod unkillable

mknod:
	sudo mknod /dev/unkillable c 117 0
	sudo chmod 666 /dev/unkillable
```

Now we just need a simple program to test our module with.

#### _immortal_process.c_

```c
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

int main()
{
	int fd;
	char c;
	char buffer[10];
	int my_pid = getpid();

	printf("My pid: %d\n", my_pid);
	fd = open("/dev/unkillable", O_RDWR);
	if (fd < 0)
		printf("Error opening /dev/unkillable\n");
	printf("Opened /dev/unkillable\n");
	read(fd, &c, my_pid);
	printf("We are now unkillable!\n");
	read(STDIN_FILENO, buffer, 10);
	printf("exiting on user input...\n");
	return 0;
}
```

Now let's put it all together. You can copy the above files into the same
folder.

```sh
$ ls
immortal_process.c  Makefile  unkillable.c
$ cc immortal_process.c 
$ make
make -C /lib/modules/5.4.0-7634-generic/build M=/home/user/unkillable modules
make[1]: Entering directory '/usr/src/linux-headers-5.4.0-7634-generic'
  CC [M]  /home/user/unkillable/unkillable.o
  Building modules, stage 2.
  MODPOST 1 modules
  CC [M]  /home/user/unkillable/unkillable.mod.o
  LD [M]  /home/user/unkillable/unkillable.ko
make[1]: Leaving directory '/usr/src/linux-headers-5.4.0-7634-generic'
$ make mknod
sudo mknod /dev/unkillable c 117 0
sudo chmod 666 /dev/unkillable
$ make uninstall
sudo rmmod unkillable
$ make install
sudo insmod unkillable.ko
$ 
```

And if we check dmesg:

```sh
[14538.243110] Inserting unkillable module
```

Now we can run our application:

```sh
$ ./a.out 
My pid: 45953
Opened /dev/unkillable
We are now unkillable!
```

From a second terminal we can check dmesg again:

```sh
[14750.576795] Unkillable: Got pid 45953
[14750.576796] Unkillable: pid 45953 marked as unkillable
```

And try to kill the process:

```sh
$ kill -9 45953
$ kill -2 45953
$ kill -15 45953
$ sudo kill -9 45953
[sudo] password for user: 
$ sudo kill -9 45953
$ ps aux | grep 'a\.out'
user    45953  0.0  0.0   2492   584 pts/4    S+   21:16   0:00 ./a.out
```

Try as we might, we cannot kill the process. Not even as root! The only way
to end the process is by giving it some input it can read so it will end
on its own. Reading input here is just an example, the process could be
performing any task. The point is that the process will continue, unkillable,
until it decides to end or the system shuts down.

```sh
$ ./a.out 
My pid: 45953
Opened /dev/unkillable
We are now unkillable!

exiting on user input...
$ 
```

# Can SIGKILL be caught?

So what comes next? It's worth pointing out that while our process is immortal,
it still cannot catch a `SIGKILL` signal. It just ignores them. Why is this?
If we search the kernel source for references to `SIGNAL_UNKILLABLE` we find
the [following snippet](https://elixir.bootlin.com/linux/latest/source/kernel/signal.c#L79)
in `kernel/signal.c`.

```c
static bool sig_task_ignored(struct task_struct *t, int sig, bool force)
{
	void __user *handler;

	handler = sig_handler(t, sig);

	/* SIGKILL and SIGSTOP may not be sent to the global init */
	if (unlikely(is_global_init(t) && sig_kernel_only(sig)))
		return true;

	if (unlikely(t->signal->flags & SIGNAL_UNKILLABLE) &&
	    handler == SIG_DFL && !(force && sig_kernel_only(sig)))
		return true;

	/* Only allow kernel generated signals to this kthread */
	if (unlikely((t->flags & PF_KTHREAD) &&
		     (handler == SIG_KTHREAD_KERNEL) && !force))
		return true;

	return sig_handler_ignored(handler, sig);
}
```

If we look for [where `sig_task_ignored()` is called](https://elixir.bootlin.com/linux/latest/source/kernel/signal.c#L101)
we find:

```c
static bool sig_ignored(struct task_struct *t, int sig, bool force)
{
	/*
	 * Blocked signals are never ignored, since the
	 * signal handler may change by the time it is
	 * unblocked.
	 */
	if (sigismember(&t->blocked, sig) || sigismember(&t->real_blocked, sig))
		return false;

	/*
	 * Tracers may want to know about even ignored signal unless it
	 * is SIGKILL which can't be reported anyway but can be ignored
	 * by SIGNAL_UNKILLABLE task.
	 */
	if (t->ptrace && sig != SIGKILL)
		return false;

	return sig_task_ignored(t, sig, force);
}
```

And if we go one layer further up, we find [where `sig_ignored()` is called](https://elixir.bootlin.com/linux/latest/source/kernel/signal.c#L961)
we find the [`prepare_signal()` function](https://elixir.bootlin.com/linux/latest/source/kernel/signal.c#L899)
which has the following helpful comment:

```c
/*
 * Handle magic process-wide effects of stop/continue signals. Unlike
 * the signal actions, these happen immediately at signal-generation
 * time regardless of blocking, ignoring, or handling.  This does the
 * actual continuing for SIGCONT, but not the actual stopping for stop
 * signals. The process stop is done as a signal action for SIG_DFL.
 *
 * Returns true if the signal should be actually delivered, otherwise
 * it should be dropped.
 */
```

Indeed, we see the final line of this function is:

```c
	return !sig_ignored(p, sig, force);
```

Thus, if our process has `SIGNAL_UNKILLABLE` set, then `sig_task_ignored()`
returns true, which causes `sig_ignored()` to return true, which causes
`prepare_signal()` to return false, which indicates that the signal should
be ignored. At no point do we get to our process's signal handling functions,
the signal is simply dropped.

Additionally, in the main loop of [`get_signal()`](https://elixir.bootlin.com/linux/latest/source/kernel/signal.c#L2526)
we find [the following code segment](https://elixir.bootlin.com/linux/latest/source/kernel/signal.c#L2673):

```c
		/*
		 * Global init gets no signals it doesn't want.
		 * Container-init gets no signals it doesn't want from same
		 * container.
		 *
		 * Note that if global/container-init sees a sig_kernel_only()
		 * signal here, the signal must have been generated internally
		 * or must have come from an ancestor namespace. In either
		 * case, the signal cannot be dropped.
		 */
		if (unlikely(signal->flags & SIGNAL_UNKILLABLE) &&
				!sig_kernel_only(signr))
			continue;
```

Now, the comment says "global init," but the code only checks for 
`SIGNAL_UNKILLABLE`. If it finds that flag, it continues to the next loop
iteration and ignores the signal. So that's two places where `SIGKILL` might
be ignored on a process flagged `SIGNAL_UNKILLABLE`.

I experimented with registering a [kthread](https://embetronicx.com/tutorials/linux/device-drivers/linux-device-drivers-tutorial-kernel-thread/)
and using that `task_struct` as the `signal->group_exit_task`. The idea is 
that when receiving a `SIGKILL` the kernel thread would use a 
[helper function](https://developer.ibm.com/technologies/linux/articles/l-user-space-apps/)
that could call `kill` to send a `SIGUSR1` to the immortal process. The
immortal process can then interpret this `SIGUSR1` as "someone is trying
to kill you," and act appropriately. I have not, however, been able to get
this working. Attempting to replace the `group_exit_task` just causes the
process to hang when receiving signals. I'm probably doing something wrong,
I just have to figure it out.

```
[  364.138308] INFO: task unkillable signal thread:4948 blocked for more than 120 seconds.
[  364.138316]       Tainted: P           OE     5.4.0-7634-generic #38~1592497129~20.04~9a1ea2e-Ubuntu
[  364.138319] "echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.
[  364.138322] test thread     D    0  4948      2 0x80004000
[  364.138328] Call Trace:
[  364.138340]  __schedule+0x2e3/0x740
[  364.138345]  schedule+0x42/0xb0
[  364.138351]  kthread+0xd5/0x140
[  364.138361]  ? init_module+0x6b/0x6b [memory]
[  364.138365]  ? kthread_park+0x90/0x90
[  364.138371]  ret_from_fork+0x35/0x40
```

And by posting this publicly on the Internet, I'm hoping some kind stranger
sets out to [prove me wrong](https://meta.wikimedia.org/wiki/Cunningham%27s_Law)
and show me how it can be done.
