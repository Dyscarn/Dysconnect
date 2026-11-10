# Base for remote call batching per frame

It's a good option to batch multiple remote calls (like FireServerConnection or FireClientConnection without REMOTE_FUNCTIONs) into a single one per frame so we don't fire an event multiple times in a single frame to try to exhaust it as little as possible.

This would allow for games to make more remote calls, thus reducing the chance of remote exhaustion while still keeping it just as manageable and foolproof.

## Okay, this actually sounds good. -- Wait, what about lag spikes? Wouldn't a really big packet cause one?

Yes, and that's why not all remote calls should be batched into a single packet.

Batch packets would have a size limit in KB to not cause lag spikes, delegating any packets that don't fit in the current frame to the next one, based on call order.

## But wouldn't this be an issue for stuff like movement and such?

Yeah, which is also why batching would be opt-in per remote call.

It'll be on by default, but you could also specify if you want to batch a specific fire or not by adding a `Dysconnect.FireOptions()` value at the end of a remote call's args.

You could even remove it by default by changing the config when initializing the service.

## Is there even anything else to talk about regarding this?

I have no idea.

## Okay, cool, cool. When did you come up with this?

While listening to my teacher rant about Spain's average salary.
