---
layout: post
title: "Revisiting Blockchain DNS"
date:   2020-08-08 15:30:00 -0400
categories: blockchain
---

I recently received an email from [Oleg Khovayko](https://www.linkedin.com/in/oleg-khovayko-78a2165/), the CTO of [Emercoin](https://emercoin.com), after he
read my original post about [blockchain DNS](/blockchain/2019/08/17/DUMPSTER.html).
He wanted to raise three points to me. The first is that emerDNS has gained a 
following in Russia for [censorship circumvention](https://roskomsvoboda.org/46197/). 
The second is that he maintains [a list](http://olegh.ftp.sh/emercoin/emcdns-live.html)
of active emerDNS domains. And the third is that they've simplified the process
of running an emerDNS resolver. That third point is nice, because it appears
that the Firefox plugin I used last year no longer works. Interestingly, when
installing the [PeerName](https://peername.com/) Chrome plugin for this post, the webstore
automatically recommended [some plugins](https://github.com/anticensority/runet-censorship-bypass)
 popular in Russia for censorship circumvention. Looks like we're on to
 something.

That first point is a very important one that I hadn't considered, since I 
live in a country
with relatively free Internet ([for now](https://www.eff.org/deeplinks/2020/03/earn-it-act-violates-constitution), anyway).
So it looks like this is worth exploring. It's also been almost exactly one
year since my [original blockchain DNS post](/blockchain/2019/08/17/DUMPSTER.html), so a followup sounds appropriate.
Let's take a look at what's happened
to blockchain-dns in the last year, and how viable it seems to be as a censorship
circumvention tool.

## Re-enumerating and re-discovering

I won't go through it again, but I simply repeated the same enumeration
steps I took [last year](/blockchain/2019/08/17/DUMPSTER.html). I upgraded to the
latest namecoin and emercoin versions and reran the python scripts. The issue I had last
year with namecoin's DNS enumeration not terminating has since been fixed, and
the whole process was pretty quick. Then I took the enumerated domains, fed
them back into [EyeWitness](https://github.com/FortyNorthSecurity/EyeWitness)
and waited for the results.

The list at [https://blockchain-dns.info/explorer/](https://blockchain-dns.info/explorer/)
says they've catalogued 5,266 sites with IPs. As you'll see in the next section,
we have quite a bit more than that. As of writing this, their list has not
been updated since October 2019. I guess a lot has happened since then. Interestingly,
this mirrors a similar pattern that's being seen in the [Tor network](https://metrics.torproject.org/hidserv-dir-onions-seen.html?start=2001-05-10&end=2020-08-08).

![a graph of onion domains over time, showing a spike in 2020](/images/dumpster2-onion.png)

Both the Peername plugin and Runet bypass plugin chrome suggested include support
for [onion domains](https://github.com/anticensority/runet-censorship-bypass/wiki/.onion,-.i2p,-OpenNIC).
Wildly speculating here, but the trend appears to be an increase in the use and
registration of these "censorship resistant" domains since the start of 2020. 
Perhaps with more people being stuck at home due to the SARS-CoV-2 
pandemic, there's been a global increase in demand for censorship resistant web
services. That would certainly mirror patterns we've seen with the general
increase in demand for regular Internet services.
 

## What's new?

Here is the categorization from EyeWitness, with a 2020 column for current
results and a 2019 column to easily compare with last year. 

| Category | Count (2020) | Count (2019) |
|----------|--------------|--------------|
| Uncategorized | 1064 | 1624 |
| Directory Listings | 4 | 9 |
| Content Management System (CMS) | 0 | 1 |
| Network Devices | 1 | 1 |
| 401/403 Unauthorized | 469 | 139 |
| 404 Not Found | 62 | 60 |
| Splash Pages | 7 | 14 |
| Internal Error | 0 | 5 |
| Bad Request | 5 | 48 |
| Errors | 6375 | 2560 |
| **Total** | 7987 | 4461 |


Right away we see we have nearly twice as many domains with A records as last year.
The categorizations are mostly the same as last year, with a noticeable increase
in 401/403 errors and general errors. Most of the new sites appear to be in the
error categories. The general errors are interesting, because
visiting some of those sites manually actually does resolve (e.g., 
[http://darksite.lib/](https://cantdoevil.ecwid.com/)). I was scraping over Tor,
so if there are more mature sites this year than last year it's possible that
many of these "error" sites are simply blocking suspicious activity. For example,
a few of the sites Oleg listed in [his post](https://roskomsvoboda.org/46197/)
do not appear on the EyeWitness report, but do appear when you navigate to
them.

Let's go through some of my favorites. There's too many sites this time to
go through them all, but a few stood out. I tried to focus on sites that
did not redirect to a regular domain address, sites that are truly committed
to blockchain DNS.

There's [this site](http://pomoyka.lib/), which is nothing but cats.

![two pictures of many cats](/images/dumpster2-cats.png)

There's [this site](http://adm1.bit/), which appears to be a meme generator.
The screenshot didn't work, but you can visit it and see for yourself.
There's [this site](http://cacta.bit), which catalogs cacti.

![a catalogue of different cactuses](/images/dumpster2-cactus.png)

There's [this site](), which appears to be a backup of the online community
[Advogato](https://en.wikipedia.org/wiki/Advogato).

![the frontpage of advogato](/images/dumpster2-advogato.png)

Besides that, there's a lot of the same credit card shops, parked domains, blogs,
and general types of sites as last year.

## Censorship Circumvention, Blockchain DNS, and OONI

Let's look at some of the sites that Oleg listed in his post, and what they're
aimed at. To the best of my knowledge, all of the content of these sites is
legal to view in the United States if you are over 18. The services, such
as gambling and pirated movies, may not be legal to use but you can look at
the advertisements. Clicking some of these links may not be legal where you are
(e.g., downloading a list of torrents or links to pornography). It's on you to 
know your local laws and decide to click these links, you have been warned. 
The full list provided is:
 
*  [http://flibusta.lib/](http://flibusta.lib/)
*  [http://nnm-club.lib/](http://nnm-club.lib/)
*  [http://rutor.lib/](http://rutor.lib/)
*  [http://rutracker.lib/](http://rutracker.lib/)
*  [http://allfon.lib/](http://allfon.lib/)
*  [http://pornolab.lib/](http://pornolab.lib/)
*  [http://booktracker.lib/](http://booktracker.lib/)
*  [http://audiokniga.lib/](http://audiokniga.lib/)
*  [http://maxima-library.lib/](http://maxima-library.lib/)
*  [http://rustorkacom.lib/](http://rustorkacom.lib/)

For this part I'm going to rely on the data collected by the 
[Open Observatory of Network Interference](https://explorer.ooni.org/).
OONI distributes a software probe that volunteers can install on their computers
that actively tests for Internet censorship in the volunteer's location.

The first site, [flibusta](http://flibusta.lib), appears to be a library of books
and is normally accessible on it's [dot is domain](http://flibusta.is/). If
we check the OONI dataset we can see [that the domain is censored in Russia](https://explorer.ooni.org/search?until=2020-08-09&domain=flibusta.is&probe_cc=RU&test_name=web_connectivity).
In fact, the front page of the site lists their tor mirrior, i2p mirror, and emerDNS
alternative domains.

Our next site is [rutor](http://rutor.lib/). This is a torrent site,
with pirated content available. Pretty standard stuff for a torrent site. Once
again, OONI shows the site as [actively censored](https://explorer.ooni.org/search?until=2020-08-09&domain=rutor.org&probe_cc=RU&test_name=web_connectivity)
on their main domain. Their ["blocking information"](http://rutor.lib/torrent/178905)
page gives some more details. The rutor.org domain has been put in a hold
by their registrar, rendering it unusable. The alternatives are listed as
two alternate registrars, tor, i2p, and again emerDNS. So it does appear that sites
are using emerDNS to circumvent censorship.

The last site we will confirm as being censored is [pornolab](http://pornolab.lib).
The main site, pornolab.net, can be confirmed by OONI as 
[somewhat censored in Russia](https://explorer.ooni.org/search?until=2020-08-09&domain=pornolab.net&probe_cc=RU&test_name=web_connectivity).
From what I can tell (I'm not Russian, so forgive my ignorance), the [legality
of pornography in Russia is dubious](https://en.wikipedia.org/wiki/Pornography_laws_by_region#Russia) (for what it's worth, it's also unclear
[here in the US](https://en.wikipedia.org/wiki/United_States_obscenity_law#Application_of_test), 
as I recently learned from reading the hilariously anti-1A
[Parler community guidelines](https://legal.parler.com/documents/guidelines.pdf)).
The Russian state has many legal apparatus
by which it can block or remove sites and services, for a variety of 
justifications. Those laws have, sometimes, included pornography, which is technically
legal to view but illegal to produce or distribute. So if you're a Russian citizen,
accessing a porn site is fine but hosting one is not. This gives the government
permission to block any "distribution" (i.e., website) as it sees fit. It's worth
noting that the site has a section for Gay pornography and another section for
Trans pornography. Russia has [propaganda ban](https://en.wikipedia.org/wiki/LGBT_rights_in_Russia#Propaganda_bans)
laws against "non-traditional sexual relationships" and [has used them against
"pornography distributors" 
before](https://www.cnn.com/style/article/yulia-tsvetkova-pornography-gay-propaganda-law-lgbtq-activism-russia/index.html).
I'm not going to make recommendations for what is or isn't safe for LGBT activists
in Russia (and let's be clear: this is a porn site, not an activist site), 
it's just interesting to note that emerDNS appears to circumvent
domain based censorship of "non-traditional sexual relationship propaganda."

## TL;DR

It appears that blockchain based DNS is a viable means of circumventing censorship
when that censorship is enacted through domain registrars. It might help with DNS
resolution based censorship, but [there are many ways to circumvent that 
already](https://ssd.eff.org/en/module/understanding-and-circumventing-network-censorship).
If IP based blocking is in place, blockchain DNS won't help and you probably
want a [VPN or Tor](https://matt.traudt.xyz/p/24tFBCJV.html). Still, I originally 
discounted the idea when it does appear to be working. I wouldn't use it for
anything that might get me arrested, but if the worst thing I'm facing is a
revocation by the registrar then sure.
