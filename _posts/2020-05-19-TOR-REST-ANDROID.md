---
layout: post
title: "How to Make API REST Requests to Tor Hidden Services in an Android APK"
date:   2022-05-19 00:00:00 -0500
categories: [android, tor]
---

**This post was originally written for the ElevenPaths Innovation and
Laboratory website, and is available
[here](https://business.blogthinkbig.com/api-rest-requests-tor-hidden-services-android-apk/).**

We were building a proof of concept in the Innovation and Laboratory Area as
part of the architecture needed to create a Tor hidden service. We also needed
a mobile application to interact with that hidden service through a JSON API.
As it turns out, there is not a lot of well documented ways to do this
seemingly straightforward task. We are sharing our notes here in case anyone
else wants to see how to add this support to their application.

If you don’t care about the background, go ahead and skip to the
“Implementation” part below.

## Background

First, let’s take a look at the different building blocks we’ll need to make
calls to a hidden service from our app. We’ll assume you have a basic
familiarity with Tor and Android app development.

### Orbot, NetCipher, and the Guardian Project

[Orbot](https://guardianproject.info/apps/orbot/) is a free application for
Android that acts as a Tor proxy for your device. You can think of it as
running the Tor service on your phone, the same as you would on any other Linux
system. Orbot is developed by [the Guardian
Project](https://guardianproject.info/), who create and maintain many privacy
oriented apps for Android. They are the team behind the officially endorsed Tor
Browser for Android, and the Orfox+Orbot combo that came before it.

However, forcing a user to install and launch Orbot before running your app is
not a friendly experience. To address this they created
[NetCipher](https://guardianproject.info/code/netcipher/). NetCipher provides,
among other things, an OrbotHelper utility class that lets your app check if
Orbot is installed, prompt the user to install it easily, and automatically
launch Orbot in the background when your app launches. It’s analogous to how
the Tor Browser bundle launches a Tor service in the background.

It’s not quite the same, though. The current official Tor Browser for Android
does away with NetCipher and Orbot as a requirement, opting to bundle Tor
within the application itself. This gives Tor Browser users across different
platforms a familiar all-in-on experience. However, since Orbot integration is
much simpler than adding a Tor daemon to our app we will use that instead.

### Volley Library and ProxiedHurlStack

On the [NetCipher library gitlab
page](https://gitlab.com/guardianproject/NetCipher/-/tree/master/) you can see
examples provided for many different Android HTTP libraries. The main supported
methods are HttpUrlConnection, OkHttp3, HttpClient, and Volley. You can also
see sample implementations for each of these techniques.

Unfortunately, these examples and the artifacts associated with them for other
HTTP clients did not work out of the box. Most of them haven’t really been
touched in at least a year, and it appears the standard method of implementing
Tor has gone from NetCipher+Orbot (analogous to proxying your local FireFox
install through Tor) to an integrated Tor service in the APK itself (analogous
to the Tor Browser bundle).

After some trial and error, it turned out you don’t really need the
`info.guardianproject.netcipher:netcipher-volley` artifact to get Tor working
in your app. If you look at the [StrongHurlStack.java
source](https://gitlab.com/guardianproject/NetCipher/-/blob/master/netcipher-volley/src/info/guardianproject/netcipher/client/StrongHurlStack.java)
you can see it’s pretty straightforward to reimplement. We also came across
[this stackoverflow
post](https://stackoverflow.com/questions/23914407/volley-behind-a-proxy-server)
describing the same concept. The example doesn’t include an `SSLSocketFactory`
like the `StrongHurlStack` does, but we can rely on Tor to provide the
[end-to-end encryption and identity assurance that SSL
would](https://2019.www.torproject.org/docs/onion-services.html.en). SSL for
Tor hidden services [is
redundant](https://blog.torproject.org/facebook-hidden-services-and-https-certs?page=1).

## Implementation

We will assume [you already have an API accessible as a hidden
service](https://jordan-wright.com/blog/2014/10/06/creating-tor-hidden-services-with-python/)
at somesite.onion.

The dependencies you need to add to your app level `build.gradle` file are the
following:

```gradle
dependencies {
    implementation 'com.android.volley:volley:1.1.1
    implementation 'info.guardianproject.netcipher:netcipher:2.1.0
}
```

Be sure to change the versions to the latest available at the time of
implementation.

Next, create a `ProxiedHurlStack.java` file and class as described in both the
NetCipher examples and the stackoverflow post and add it to your project.

```java
package your.app.here;

import com.android.volley.toolbox.HurlStack;
import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.InetSocketAddress;
import java.net.Proxy;
import java.net.URL;

public class ProxiedHurlStack extends HurlStack {
    @Override
    protected HttpUrlConnection createConnection(URL url) throws IOException {
        Proxy proxy = new Proxy(
                Proxy.Type.SOCKS,
                InetSocketAddress.createUnresolved("127.0.0.1", 9050)
        );
        return (HttpURLConnection) url.openConnection(proxy);
    }
}
```

Now in our `MainActivity.java` file we can import all the relevant libraries.

```java
package your.app.here;

import com.android.volley.Request;
import com.android.volley.RequestQueue;
import com.android.volley.Response;
import com.android.volley.VolleyError;
import com.android.volley.toolbox.JsonObjectRequest;
import com.android.volley.toolbox.Volley;

import org.json.JSONObject;

import info.guardianproject.netcipher.proxy.OrbotHelper;
```

Next, we call
[`init()`](https://github.com/guardianproject/NetCipher/blob/master/libnetcipher/src/info/guardianproject/netcipher/proxy/OrbotHelper.java#L534)
and
[`installOrbot()`](https://github.com/guardianproject/NetCipher/blob/master/libnetcipher/src/info/guardianproject/netcipher/proxy/OrbotHelper.java#L576)
from our `onCreate()` method to spin up Orbot in the background. If Orbot is
already installed, `init()` will return `true` and prompt Orbot to connect to
the Tor network. If Orbot is not already installed, `init()` will return
`false` and the user will be taken to the Play Store and prompted to install
Orbot.  When installation finishes the app will tell Orbot to create a
connection to the Tor network.

```java
@Override
protected void onCreate(Bundle savedInstanceState) {

    // ... other actions here ...

    if (!OrbotHelper.get(this).init()) {
        OrbotHelper.get(this).installOrbot(this);
    }
}
```

Now we can build a JSON request to our hidden service. You would add this next
part wherever you send requests to your API.

```java
JSONObject jsonBody = new JSONObject("{\"your payload\": \"goes here\"}");
RequestQueue queue = Volley.newRequestQueue(this, new ProxiedHurlStack());
String url = "http://somesite.onion/your/api/endpoint/here";

JsonObjectRequest jsonRequest = new JsonObjectRequest(
    Request.Method.POST, url, jsonBody,
    new Response.Listener<JSONObject>() {
        @Override
        public void onResponse(JSONObject response) {
            // do something with the response
        }
    },
    new Response.ErrorListener() {
        @Override
        public void onErrorResponse(VolleyError error) {
            // do something with the error
        }
    }
);

queue.add(jsonRequest);
```

And that’s it! Now you can test your app and see API calls being made to your
hidden service.

