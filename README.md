<!--README.md based on Promise's (https://github.com/evaera/roblox-lua-promise) because I liked it.-->

<div align="center">
	<h1>Dysconnect</h1>
	<p>A networking library for Roblox designed to simplify communication between the client and server, with support for remote events, remote functions, and network exhaustion detection.</p>
</div>

<!--moonwave-hide-before-this-line-->

## Why you should use Dysconnect

Roblox provides built-in networking objects such as RemoteEvent, UnreliableRemoteEvent, and RemoteFunction. While these are crucial to making any game in the platform, managing them directly across a project can lead to repetitive setup and inconsistent networking patterns, apart from having the ability to be more compressed using [buffers](https://create.roblox.com/docs/reference/engine/libraries/buffer).

Examples of this are having folders for each type with tens of instances in them, and though they can be organized through folders, it's not ideal to have many references to those in any scripts, mainly for organization.

Dysconnect aims to make networking easier to organize and use by providing a unified interface for supported communication types, apart from optimizing network as much as possible while keeping commodity intact.

* **Simplified networking**: Work with supported network objects through a consistent API.

* **Multiple communication types**: Support for reliable remote events, unreliable remote events, and remote functions.

* **Client-server communication**: Organize communication between clients and the server.

* **Network exhaustion detection**: Help protect against excessive remote requests with configurable per-player rate limiting.

* **Configurable behavior**: Adjust network exhaustion detection settings to suit your experience.

## Supported types

Dysconnect supports almost every type of network instance:

* [RemoteEvents](https://create.roblox.com/docs/reference/engine/classes/RemoteEvent)
* [UnreliableRemoteEvents](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent)
* [RemoteFunctions](https://create.roblox.com/docs/reference/engine/classes/RemoteFunction)
* [BindableEvents](https://create.roblox.com/docs/scripting/events/bindable)

[BindableFunctions](https://create.roblox.com/docs/reference/engine/classes/BindableFunction) aren't supported due to their rare usage (at least personally) but might be in a future update.

## Buffering and serialization

Dysconnect uses Roblox's [buffer](https://create.roblox.com/docs/reference/engine/libraries/buffer) library to serialize supported values into a compact binary representation before transmitting them over the network.

Instead of relying solely on Roblox's default argument serialization, Dysconnect encodes values into a single buffer using a type-tagging system. Each value is assigned a type identifier, allowing the receiving side to determine how to decode it.

This approach provides several optimizations:

* **Compact data representation**: Numbers use appropriately sized int or float representations where supported (bit-size wise).

* **Precomputed payload sizes**: Fixed-size data types have predefined sizes, avoiding repeated size calculations for those values.

* **Custom serialization**: Supported types (including [Vector2](https://create.roblox.com/docs/reference/engine/datatypes/Vector2), [Vector3](https://create.roblox.com/docs/reference/engine/datatypes/Vector3), [CFrame](https://create.roblox.com/docs/reference/engine/datatypes/CFrame), [Color3](https://create.roblox.com/docs/reference/engine/datatypes/Color3), [UDim2](https://create.roblox.com/docs/reference/engine/datatypes/UDim2), [TweenInfo](https://create.roblox.com/docs/reference/engine/datatypes/TweenInfo) and other Roblox data types) have dedicated encoding and decoding logic.

* **Table serialization**: Each key and value in a table carries its own type identifier so it's possible to encode every key and value individually.

Strings, existing buffers, and JSON-encoded values are length-prefixed, allowing the decoder to determine where each payload ends. Values that use JSON encoding can also be represented through the same tagged serialization system.

The actual savings depend on the values being transmitted and how Roblox's default serialization represents them. Performance and bandwidth improvements should be measured against representative workloads rather than assumed for every payload.

Something to note is that [Instances](https://create.roblox.com/docs/reference/engine/classes/Instance) aren't serialized into buffers for one main reason: serializing an Instance would mean turning it into a .rbxm file using [SerializationService](https://create.roblox.com/docs/reference/engine/classes/SerializationService) and deserializing it in client, effectively making a copy of the same Instance. This is something that shouldn't usually be done over the network as it'd take up a lot of space, and it's just better to recreate those instances in client if really needed to (like hitbox visualizers) with the bare minimum data required to do so. Instance serializing isn't included in this package to enforce good practices networking-wise, preventing so much data to be sent unnecessarily.

## Network exhaustion detection

Dysconnect includes network exhaustion detection to help mitigate excessive remote requests from individual players (DDoS).

Its configuration includes a usage threshold, a recovery rate, and a modifier controlling how UnreliableRemoteEvent calls contribute to accumulated usage.

The detection system is configurable to accommodate different networking requirements.

## Alternatives

Of course, there are many other good alternatives out there to check out.
* [Packet](https://devforum.roblox.com/t/packet-networking-library/3573907): Similar to this package, but with different usage, allowing you to make individual event objects (NOT instances).
* [Warp](https://imezx.github.io/Warp/): Supports schemas and is also very similar to typical events.
* [ByteNet](https://ffrostfall.github.io/ByteNet/): Minimizes packet size as much as possible using schemas to define events, saving on sending value types and position pointers, though is harder to use.

Dysconnect was made to keep everything centralized in a single place and to be the most simple to use out of them all while keeping most of that network performance gain.

## License

See the [license](LICENSE.md) for more information.
