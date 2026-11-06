# Base for Shared IDs for Remote names in each side

Initially, I was going to use MadStudioRoblox's Replica for this. But, seeing that I'd have to import it manually (no Wally package) and that I'd have to handle importing it to a server container from Wally, I don't want to be so messy.

I struggled to figure out a way to do this dynamically and automatically while meeting these criteria:
* It must be safe for server so exploiters can't just register thousands of IDs with unused remotes
* It mustn't require manually changing a registry (since that's not the point of this, there are other libraries with schemas already)
* It must 

I came up with a proper method to do this in the middle of English class for some reason. We're *that* bored.

## How are the IDs gonna be synced?

We keep track of the IDs in a server-side table that's replicated to all the clients. When a client joins, the table is sent to it to replicate all the existing IDs.

Remote #0 would be reserved and locked out of the ID list to use for internals for this system.

Then, when a new ID is registered, it'd either be sent through another reserved remote event or through the same one.

## When are the IDs registered?

Whenever `Dysconnect.SetConnection()` is called on the server, its name is registered with an ID that is sent through #0 to all clients.

## What about client-side connections?

If we tried to register it on `Dysconnect.SetConnection()`, we would have to send it to the server, causing desyncs and vulnerabilities for exploiters.

So, whenever we fire a RemoteEvent to any client from the server, we register THAT name, THEN fire the remote we were going to fire with its new ID.

So if we try to fire "CamShake" to a client and it's not registered yet, it'll register it with an ID directly, send that to the client, then fire the remote with the ID.

On the client side, it'd wait for that ID to exist in its table for a set amount of time (as a timeout) and, if it finds it in that timespan, it'll execute the callback assigned to that name.

## Wait, but if SetConnection is called many, many times in server, wouldn't that fire the same remote a bunch of times?

Yes, and it would cause a lag spike and maybe even drop some packets, meaning those IDs won't be registered at all.

We fix that by, instead of sending them individually, we add them to an ID batch that'll send multiple registered IDs in only one fire in a single frame.

## But wouldn't this cause exhaustion / lag spikes when the game is initializing anyways?

For this, I have to explain something else.

The client has to first set a connection to Remote #0 in order to receive the initial list. There's no way of checking this in server without involving the client itself.

When initializing the client side, it should fire a reserved remote for saying "I'm ready, send me the damn thing!" so the server sends it the entire list.

Since this module is mostly intended to be used in module loaders, it'd be okay to assume that the server connections will have been done by the time any client initializes all its scripts.

Of course, this is only an option if client modules are initialized AFTER loading assets. This isn't a reason to rule out batching multiple connections made in the same frame to one remote event. That'll still be done, but we must mitigate as much as possible.

I'm still open to Pull Requests from anyone to improve on this.

## And wouldn't the client be able to initialize BEFORE the server can connect to the Ready connection?

Okay, this is an insanely rare occurrence. BUT, it's a possibility.

For that we can literally just set an attribute on either workspace or the module itself called "DysconnectServerReady" that the clients check so they wait until the server is ready to accept those fires.

## This might be a bit funky...

Yeah, I came up with it during an English class. What do you think my mind was on?

## But, uhh... hold on let me think... uhh...

bro.

## I- Is this gonna actually make a difference?

For people that make long ass names for remote events, yes.

It also makes the module look more appealing.
