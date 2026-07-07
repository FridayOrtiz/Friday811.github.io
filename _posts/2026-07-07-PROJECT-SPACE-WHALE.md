---
layout: post
title: "Project Space Whale: A Love Letter to the Browser Games and MMOs I Played on Ubuntu in 2005"
date: 2026-07-07 16:00:00 -0400
categories: gaming
tags: [gaming, rust]
---

**TL;DR:** [Go play it, dawg.](https://ortiz.sh/game/)

## The Jedi Problem

This all started because a friend sent me a link to [this excellent noclip
documentary](https://youtu.be/UAv0LYLQi5c). The noclip crew interviews an
original team member behind Star Wars: Galaxies, the greatest sandbox MMO of all
time, and goes into how the team dealt with (or failed to deal with) the fact
that everyone wants to be a Jedi in a world that canonically can't have many
Jedi.  It's a great documentary. You should check it out.

> Friend: https://youtu.be/UAv0LYLQi5c @Friday you may enjoy this
> Me: tragic that there can never be another mmo like this

SWG came about in an era where the line between the MUDs of the past and the
MMOs of the future was visible in every player interaction. Runescape was also a
child of this era. The original vanilla WoW too, to a lesser degree. SWG had a
chat option called DikuMUD, which would format your chat window MUD-style.  The
slash commands, still present in MMOs, came from these proto-MMO online shared
text adventures.

The problem the SWG team ran into was, in my view, that the MMO players of the
era were simply not hardcore enough to face up to Jedi properly. Their original,
beautiful, vision, turned Jedi into a roguelike mode. Something hard to get a
character into, that activated permadeath, where your eventual death would turn
into bragging rights about how far you got. For gamers raised on nethack and
aardwolf this makes all the sense in the world. But, to be fair, if you were
coming from Everquest it's pretty jarring.

SWG, and other MMOs of the era, also did something many (most? all?) MMOs have
since abandoned: it forced you to talk to people. If you wanted to figure out
how to be a Jedi, you had to talk to people. If you wanted to go somewhere, you
had to wait for a shuttle to show up, and while you were waiting you talked to
people. In the original WoW, you sat on a zeppelin and had to talk to people. In
the original Runescape, you'd get stuck on a quest and have to... talk to
people. MMOs were social, because MUDs were social. They had to be! You only had
text to work with!

I have been toying with, for years on and off, the idea of a nethack style game
you could play with other people. Not quite a MUD, which is too much of a high
friction interface for the modern user, and not a proper game with graphics,
because I can't draw, but something in between. I've written a few prototypes
over the years, some more MUD and less nethack, some more nethack and less MUD,
but none of them getting very far. The issue I kept running into was that all
these projects quickly turned from designing a game (fun) and implementing game
systems (very fun) into building netcode, managing server infrastructure, and
other boring, tedious tasks.

How quickly my lamentation became joy when I realized, shortly after finishing
that noclip documentary...

> Me: fuck it I have a claude license

## In The Beginning, There Was MUD

How, then, to vibe a game into existence? I've messed around with vibe coding a
bit, for career driven reasons, and have experienced enough of it to know it
sucks at anything that has a visual element to it. How can an LLM drive a test
of something it can't see? Poorly, is the answer. 

The solution was to make the entire game playable like a MUD, over the wire. The
design is purely server-authoritative, where the game's simulation runs across
several shards. The client sends commands, which the server executes or rejects,
and sends a message back. The GUI paints an interface for the player based on
the contents of these replies, but it is (theoretically) possible to play the
whole thing by command only. This lets the LLM write and drive tests for things
like movement, combat, quest completion, even minigames, in a way that mostly
solves the problems of getting AI to work on a game.  Mostly. There's still a
ton of manual development and testing.

As I went along, using the command line wore on me, so I built a TUI. After a
while, the TUI started having really irritating limitations, so I settled on a
Rust egui, compiled to wasm, distributed on this very website. The MUD bones are
still visible in many parts of the game, which is confusing and inconsistent in
a way that feels very true to the spirit of the old MMOs that inspired me.

> Friend: friday is making scifi runescape from first principles

The game now has quests, NPCs, combat, skills, interactions, markets, and many
of the other features you'd expect from a game like this. And bugs. So very many
bugs. I playtest everything, and still they slip past me. My friends have been
kind enough to mostly report them to me so I can hammer them out.

## I Caught a Vibe

"What the fuck, man?" I hear you say, misgendering unintentionally with a vulgar
idiom. "I can't believe you're using AI for this.  How am I supposed to trust
you?" I mean, don't.  I'm not asking for your credit card here, nor would I for
a project like this. I'm a Linux hacker by trade, not a web app security
specialist, so don't reuse an old password on here either (you're already using
a password manager, right?).

"No dude," you continue, "I mean, couldn't you have written this yourself?" Well
no, I couldn't have. I mean, literally yes I could have, and have started to
many times. But there's a lot of solved-problem boilerplate code involved in
wiring up projects like this. And LLMs are really, really, good at all that
boring crap. It was do it myself never, or do it with an LLM today.

I have a professional interest in LLMs. People run these things on Linux
systems, and I am paid to defend them. I am contractually obligated to
understand how these harnesses work, so it does pay off for me to use them on my
own time the same way I mess with my own Linux systems on my own time. Although
I retain the right to privately complain if I see someone doing something silly
or foolish with them, a right irl friends know I exercise regularly.

On the environmental impact of AI, spending as much time outdoors as I do has
made it abundantly clear that you can't be alive without leaving a trace. I was
vegan for a while. Not having a kid has a huge, positive, environmental impact.
Living in a detached house has a huge, negative, one. Every time I pull a weed
from my garden I am reminded of the forest and the meadow that once stood here.
I am politically active in ways that attempt to curb these impacts, and that I
don't feel are appropriate to share online.  We all have to draw a line
somewhere. Mine is somewhere past "LLM used for writing code," and before "gives
money to JK Rowling." Yours is up to you.

## jk... unless??

"Okay, but you still could've paid an artist!" Well, I'd like to, but I'm not
going to for a silly little hobby project nobody is interested in. I certainly
wouldn't charge money for slop. If by some weird confluence of fate people do
start playing this thing, I'd love to pay an actual writer to clean things up,
and an actual artist to build assets.

Until then, I will keep hacking away at this thing. Adding little features and
little tasks to my little toybox that anyone is invited to come stomp around in.