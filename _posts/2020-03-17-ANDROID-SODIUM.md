---
layout: post
title:  "Integrating Libsodium SealedBox into an Android Studio Project"
date:   2020-03-20 18:30:00 -0400
categories: android
tags: [android, cryptography]
---

This post documents my attempt to get [libsodium-jni](https://github.com/joshjdevl/libsodium-jni)
with [SealedBox](https://libsodium.gitbook.io/doc/public-key_cryptography/sealed_boxes)
support working in an Android Studio project. It assumes you already have an
Android Studio project up and running (and that you've accepted all the 
licenses!) that you wish to add libsodium to. I am running Pop!\_OS 19.10, but 
this should work on Ubuntu 19.10 and related distros.

```sh
$ lsb_release -a
No LSB modules are available.
Distributor ID:	Ubuntu
Description:	Pop!_OS 19.10
Release:	19.10
Codename:	eoan
```

**Update 19 Apr, 2020:** Be careful with these instructions if
you are also developing C projects that rely on `sodium.h`. Installing
libsodium from git as described here will conflict with installing it from
your distro's `libsodium23` and `libsodium-dev` packages.

## Background

I was working on an Android application that required the use of libsodium's
SealedBox. A public private key pair is first generated out of band and then
the public key is communicated by some means to the mobile device. The mobile
device needs to take some piece of information, encrypt it with the
public key using SealedBox, and return the encrypted blob. 

The `nacl` python module is great at this, but there were no easy answers for
Android. I am not a  cryptographer which is why I wanted to stick with a 
misuse-resistant library like libsodium. I know there are many alternatives,
but the hope is that this library should make it hard for me to mess up.

I looked around for ways to integrate [libsodium with Android](https://stackoverflow.com/questions/26856443/android-eclipse-jedisct1-libsodium-where-to-start/)
and all signs pointed to kalium-jni, which is now called [libsodium-jni](https://github.com/joshjdevl/libsodium-jni)
presumably to avoid confusion with [kalium](https://github.com/abstractj/kalium).
Libsodium-jni promises to add a Java JNI binding for NaCl that can be used in
Android APKs. Sounds great! But there were a few problems.

First, the project as is [does not support SealedBox](https://github.com/joshjdevl/libsodium-jni/issues/126).
This means I couldn't just use the pre-built binary in the [Sonartype OSS repo](https://oss.sonatype.org/#nexus-search;quick~libsodium),
I had to build it myself and include SealedBox somehow. I decided to make 
[my own fork](https://github.com/Friday811/libsodium-jni) and pull in the 
[SealedBox implementation made by om26er](https://github.com/joshjdevl/libsodium-jni/pull/127)
from the [implement-sealed-box branch](https://github.com/om26er/libsodium-jni/tree/implement-sealed-box).

Second, the instructions for building the project were not a good fit for my
workflow. The instructions are based around a one-size-fits-all script that
seems to just force the build to work with no regard for the individual host
configuration. I'm not knocking the original dev, I realize this isn't an easy
problem to solve and it probably helps with build issues, but it wasn't going
to work for me. For example, it relies on a `setenv.sh` file that overwrites
environment variables and may not be correct:

```sh
export PATH=${NDK_ROOT}:$PATH
export JAVA_HOME=/usr/lib/jvm/java-8-oracle
export ANDROID_NDK_HOME=${NDK_ROOT}
export ANDROID_HOME=`pwd`/installs/android-sdk
```

I'm not using the Oracle JDK, so this wouldn't work for me. Also, the 
`dependencies-linux.sh` script just adds repositories and installs unrelated
software:

```sh
sudo apt-get -qq update && sudo apt-get -y -qq install python-software-properties software-properties-common
sudo add-apt-repository -y "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) universe"
sudo apt-get -qq update

sudo add-apt-repository ppa:git-core/ppa -y
sudo apt-get -qq update

sudo add-apt-repository -y ppa:saiarcot895/myppa
sudo apt-get -qq update
echo debconf apt-fast/maxdownloads string 16 | sudo debconf-set-selections
echo debconf apt-fast/dlflag boolean true | sudo debconf-set-selections
echo debconf apt-fast/aptmanager string apt-get | sudo debconf-set-selections
sudo apt-get -y -qq install apt-fast 
```

I don't need `apt-fast`, thanks. Just tell me the dependencies and I'll sort 
them out on my own. So the next thing I needed to do was discover what the
true dependencies were and install only those. 

## Just tell me how to get it working!

I'm assuming you are running Linux (Ubuntu 19.10 or similar), have Android 
Studio installed, and already have an up and running project to import 
libsodium into.

### Install Dependencies

As far as I could tell, the true dependencies are:

 - git
 - autoconf
 - automake
 - build-essential
 - autogen
 - libtool
 - gettext-base
 - gettext
 - libpcre3-dev
 - libpcre++-dev
 - pkg-config
 - maven
 - lldb
 - clang
 - swig

I am unsure of `wget`, `bzip2`, and `unzip`, but it can't hurt. The 
copy-pasteable command is:

```sh
sudo apt-get install wget git autoconf automake build-essential autogen libtool gettext-base gettext bzip2 libpcre3-dev libpcre++-dev pkg-config unzip maven lldb clang swig
```

Gradle is left out because we will use the version that comes with your
project's `gradlew` wrapper script.

Next, you should install the [Android NDK](https://developer.android.com/studio/projects/install-ndk)
for Linux. The instructions on that page are pretty easy to follow if you're
using the SDK Manager.

And that's it, you're ready to start building.

### Build the AAR

First, clone the repository. You can use my fork which already has the
SealedBox included or you can fork it and pull it yourself.

```sh
$ git clone https://github.com/Friday811/libsodium-jni
Cloning into 'libsodium-jni'...
remote: Enumerating objects: 48, done.
remote: Counting objects: 100% (48/48), done.
remote: Compressing objects: 100% (27/27), done.
remote: Total 4320 (delta 9), reused 33 (delta 6), pack-reused 4272
Receiving objects: 100% (4320/4320), 1.48 MiB | 4.16 MiB/s, done.
Resolving deltas: 100% (2078/2078), done.
$ cd libsodium-jni/
```

Next, you'll want to initialize the libsodium submodule and set it to the
latest stable version.

```sh
$ git submodule init
Submodule 'libsodium' (https://github.com/jedisct1/libsodium) registered for path 'libsodium'
$ git submodule sync
Synchronizing submodule url for 'libsodium'
$ git submodule update
Cloning into '/home/user/Documents/github/libsodium-jni/libsodium'...
Submodule path 'libsodium': checked out '6bece9c8c45259998f83ce243b1933e76c03f545'
$ git branch
* (HEAD detached at 6bece9c8)
  master
$ git checkout master
Previous HEAD position was 6bece9c8 Relax most __attribute__ ((nonnull)) to allow 0-length inputs to be NULL.
Switched to branch 'master'
Your branch is up to date with 'origin/master'.
$ git checkout stable
Branch 'stable' set up to track remote branch 'stable' from 'origin'.
Switched to a new branch 'stable'
$ git pull origin stable
From https://github.com/jedisct1/libsodium
 * branch              stable     -> FETCH_HEAD
Already up to date.
```

That last  pull wasn't necessary but I'm paranoid. I commit the latest 
libsodium stable back to the repo, you can too if you have your own fork.
It's not really necessary though, you can just pull the latest libsodium
whenever you want to rebuild.

Next, we want to generate the source from SWIG. Unfortunately, the
version of gradle in the Ubuntu repos is out of date and won't work properly,
which is why I didn't include it as a dependency earlier.

```sh
$ gradle --version
------------------------------------------------------------
Gradle 4.4.1
------------------------------------------------------------

Build time:   2012-12-21 00:00:00 UTC
Revision:     none

Groovy:       2.4.16
Ant:          Apache Ant(TM) version 1.10.6 compiled on July 11 2019
JVM:          12.0.2 (Private Build 12.0.2+9-Ubuntu-119.04)
OS:           Linux 5.3.0-7629-generic amd64
```

However, we can use the gradle wrapper script that is found in the root
folder of any Android project. I committed it to my repo, so you can use
that if you like or you can copy in your own.

If you want to copy your own, you'll need the `gradlew` file as well
as the `gradle/wrapper/gradle-wrapper.jar` and 
`gradle/wrapper/gradle-wrapper.properties` files. Copy the script, jar file,
and properties file to the root of the libsodium-jni folder. Make sure you
preserve the `gradle/wrapper/` subfolder path for the jar and properties
files.

Now we have a more up to date gradle we can use to build the rest of the
project.

```sh
$ ./gradlew --version

------------------------------------------------------------
Gradle 5.6.4
------------------------------------------------------------

Build time:   2019-11-01 20:42:00 UTC
Revision:     dd870424f9bd8e195d614dc14bb140f43c22da98

Kotlin:       1.3.41
Groovy:       2.5.4
Ant:          Apache Ant(TM) version 1.9.14 compiled on March 12 2019
JVM:          12.0.2 (Private Build 12.0.2+9-Ubuntu-119.04)
OS:           Linux 5.3.0-7629-generic amd64

$ 
```

Next, you'll want to generate the SWIG source.

```sh
$ ./gradlew generateSWIGsource --full-stacktrace
Starting a Gradle Daemon, 1 incompatible Daemon could not be reused, use --status for details

BUILD SUCCESSFUL in 35s
1 actionable task: 1 executed
```

After that we can build libsodium itself. I have 6 cores, but
you should adjust the number in `make -j6` to your number of cores.

```sh
$ cd libsodium/
$ ./configure --disable-soname-versions --prefix=`pwd`/libsodium-host --libdir=`pwd`/libsodium-host/lib
... lots of configure text ...
$ make clean
... lots of make text ...
$ make -j6
... lots of make text ...
$ make install
... lots of make text...
```

Now we build the ndk version of libsodium. You'll need to set the
`ANDROID_NDK_HOME` and `JAVA_HOME` environment variables. Make sure you include
the version number for the ndk path.

Here is how I set up my Android paths in my `.bashrc`:

```sh
export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/21.0.6113669/
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools
```

Now we can build libsodium for the Android NDK. My openjdk Java home is 
located at `/usr/lib/jvm/default-java/`, but yours may vary.
The output AAR file can be found at 
`build/outputs/aar/libsodium-jni-release.aar`.

```sh
$ export JAVA_HOME=/usr/lib/jvm/default-java/
$ ./gradlew build --full-stacktrace
...
BUILD SUCCESSFUL in 20s
70 actionable tasks: 25 executed, 45 up-to-date
```

At this point we can import the AAR into Android Studio. There are a few
other steps that will allow us to use libsodium on the host which may
make development easier, if desired. If you don't care about this you can
skip down to the next section.

Next we build `libsodiumjni.so` object and add it to our host library. This
script feels sketchy since it asks for `sudo` privileges, but you can
see below that it's pretty benign.

```sh
$ cd jni/
$ ./jnilib.sh 
#!/bin/bash -ev

jnilib=libsodiumjni.so
destlib=/usr/lib
if uname -a | grep -q -i darwin; then
  jnilib=libsodiumjni.jnilib
  destlib=/Library/Java/Extensions
  if [ ! -d $destlib ]; then
      sudo mkdir $destlib
  fi
else
  sudo ldconfig
fi
[sudo] password for user: 
echo $jnilib
libsodiumjni.so
echo $destlib
/usr/lib
echo $destlib/$jnilib 
/usr/lib/libsodiumjni.so

#sudo cp /usr/local/lib/libsodium.* /usr/lib

SODIUM_LIB_DIR=../libsodium/libsodium-host/lib

gcc -I../libsodium/src/libsodium/include -I${JAVA_HOME}/include -I${JAVA_HOME}/include/linux -I${JAVA_HOME}/include/darwin sodium_wrap.c -shared -fPIC -L${SODIUM_LIB_DIR} -L/usr/local/lib -L/usr/lib -lsodium -o $jnilib
sudo rm -f $destlib/$jnilib
sudo cp $jnilib $destlib
sudo cp ${SODIUM_LIB_DIR}/libsodium.so /usr/lib
$ cd ../
```

Finally, we get to the Maven build. I had issues with javadoc so I just 
skipped that part. If I want the docs I'll read the source files.

```sh
$ mv -q clean install
[ERROR] Failed to execute goal org.apache.maven.plugins:maven-javadoc-plugin:3.2.0:jar (attach-sources) on project libsodium-jni: MavenReportException: Error while generating Javadoc: 
[ERROR] Exit code: 1 - javadoc: error - The code being documented uses modules but the packages defined in https://docs.oracle.com/javase/7/docs/api/ are in the unnamed module.
...
$ mvn -Dmaven.javadoc.skip=true -q clean install

...
Results :

Tests run: 97, Failures: 0, Errors: 0, Skipped: 0
```

We get a bunch of warnings, but no errors. The compilation has tests but you
can explicitly run more tests if you'd like.

```sh
$ ./singleTest.sh 
#!/bin/bash -ev

echo "running single test to find stacktrace if track down JNI loading error"
running single test to find stacktrace if track down JNI loading error
mvn --quiet clean test -Dtest=RandomTest#testProducesDifferentDefaultRandomBytes
WARNING: An illegal reflective access operation has occurred
WARNING: Illegal reflective access by com.google.inject.internal.cglib.core.$ReflectUtils$1 (file:/usr/share/maven/lib/guice.jar) to method java.lang.ClassLoader.defineClass(java.lang.String,byte[],int,int,java.security.ProtectionDomain)
WARNING: Please consider reporting this to the maintainers of com.google.inject.internal.cglib.core.$ReflectUtils$1
WARNING: Use --illegal-access=warn to enable warnings of further illegal reflective access operations
WARNING: All illegal access operations will be denied in a future release

-------------------------------------------------------
 T E S T S
-------------------------------------------------------
Running org.libsodium.jni.crypto.RandomTest
Mar 20, 2020 9:57:23 AM org.libsodium.jni.NaCl <clinit>
INFO: librarypath=/usr/java/packages/lib:/usr/lib/x86_64-linux-gnu/jni:/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:/usr/lib/jni:/lib:/usr/lib
Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.073 sec

Results :

Tests run: 1, Failures: 0, Errors: 0, Skipped: 0

#mvn clean test -Dtest=RandomTest#testProducesDifferentDefaultRandomBytes -X
```

### Use the AAR

The steps here are taken straight from the 
[Android developer docs](https://developer.android.com/studio/projects/android-library).

First, launch Android Studio and open your project. Now we want to add the
compiled AAR to the project. Click **File > New > New Module**, then
**Import .JAR/.AAR Package**, navigate to the AAR file at
`/path/to/libsodium-jni/build/outputs/aar/libsodium-jni-release.aar`, and
you're done. The following line in your `settings.gradle` should be added 
automatically, but you can double check that it's there:

```gradle
include ':app', ':libsodium-jni-release'
```

Additionally, you should add the library as a dependency in the app level
`build.gradle` file.

```gradle
dependencies {
  implementation project(":libsodium-jni-release")
}
```

To use the code in your project you can import what you need and get to work.
If you've used libsodium wrappers before this should be pretty straightforward.

```java
import org.libsodium.jni.keys.PublicKey;
import org.libsodium.jni.crypto.SealedBox;
```

I was coming from a python space so the usage was a bit different. You can
check the SealedBox source, but basically you have to transform stuff to
bytes/string in a more manual way:

For example:

```java
public SealedBox(byte[] publicKey) {
    if (publicKey == null) {
        throw new IllegalArgumentException("Public key must not be null");
    }
    mPublicKey = publicKey;
}
```

I could have added a constructor that uses PublicKey but I'm lazy and 
calling `toBytes()` on the `PublicKey` was easy enough. And that's it, you
can now use libsodium and SealedBox in your Android project.
