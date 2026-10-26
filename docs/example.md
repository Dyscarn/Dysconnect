---
sidebar_position: 3
---

# Usage & Examples

## Initialization

Before using Dysconnect, you need to initialize it on both the server and the client.

First, place the `Dysconnect` ModuleScript and its `DataTypes` submodule in `ReplicatedStorage`, preserving the hierarchy expected by your module.

Create a Script inside `ServerScriptService`:

```lua
local Dysconnect = require(game:GetService("ReplicatedStorage").Dysconnect)

Dysconnect.Init()
```

Then, create a LocalScript inside `StarterPlayerScripts`:

```lua
local Dysconnect = require(game:GetService("ReplicatedStorage").Dysconnect)

Dysconnect.Init()
```

Calling `Init()` sets up the networking instances and connections for the current environment. You should initialize the module once in each environment before using it.

## Creating a connection

Connections are registered with `SetConnection()`. Each connection has a name, a type, and a callback that runs when the connection is fired.

For example, register a connection on the server:

```lua
Dysconnect.SetConnection("PrintMessage", "REMOTE_EVENT", function(player: Player, message: string)
    print(player.Name .. " sent:", message)
end)
```

The first argument is the connection's name, `"REMOTE_EVENT"` specifies the type, and the callback receives the arguments sent with the event. On the server, the callback's first parameter is always the `Player` who fired the remote.

## Firing a connection

Once a connection is registered, you can fire it from the other side using `FireServerConnection()` or `FireClientConnection()`.

For example, in a LocalScript, send a message to the server:

```lua
Dysconnect.FireServerConnection("PrintMessage", "REMOTE_EVENT", "Hello from the client!")
```

The server's registered callback will receive `"Hello from the client!"` as its `message` argument.

To send a message from the server to a specific client, use `FireClientConnection()`:

```lua
Dysconnect.FireClientConnection(player, "DisplayMessage", "REMOTE_EVENT", "Hello from the server!")
```

Register the corresponding connection in the client:

```lua
Dysconnect.SetConnection("DisplayMessage", "REMOTE_EVENT", function(message: string)
    print(message)
end)
```

Notice that the target `Player` is the first argument to `FireClientConnection()`, before the connection name and type.

## Broadcasting to all clients

Use `FireAllClientConnection()` to send a remote event to every connected client.

On the server:

```lua
Dysconnect.FireAllClientConnection("RoundStarted", "REMOTE_EVENT", "The round has started!")
```

On each client:

```lua
Dysconnect.SetConnection("RoundStarted", "REMOTE_EVENT", function(message: string)
    print(message)
end)
```

You can use `"UREMOTE_EVENT"` instead of `"REMOTE_EVENT"` when unreliable delivery is appropriate.

## Remote functions

Remote functions allow the caller to receive return values from the other side.

Register a remote function on the server:

```lua
Dysconnect.SetConnection("GetPlayerLevel", "REMOTE_FUNCTION", function(player: Player): number
    -- Replace this with your own level lookup.
    return 10
end)
```

Then invoke it from a LocalScript:

```lua
local level = Dysconnect.FireServerConnection("GetPlayerLevel", "REMOTE_FUNCTION")

print("Your level is:", level)
```

The value returned by the server callback is returned to the client. Remote function calls yield while waiting for the other side, so use them when a response is actually needed.

You can also invoke a client from the server with `FireClientConnection()`:

```lua
local setting = Dysconnect.FireClientConnection(
    player,
    "GetClientSetting",
    "REMOTE_FUNCTION",
    "MusicEnabled"
)
```

The client must register the corresponding connection using `SetConnection()`.

## Unreliable remote events

Use `"UREMOTE_EVENT"` for frequent updates where occasional packet loss is acceptable, such as cosmetic effects or rapidly changing visual information.

On the client:

```lua
Dysconnect.FireServerConnection("UpdateAimDirection", "UREMOTE_EVENT", Vector3.new(0, 0, -1))
```

On the server:

```lua
Dysconnect.SetConnection("UpdateAimDirection", "UREMOTE_EVENT", function(player: Player, direction: Vector3)
    print(player.Name, direction)
end)
```

Unreliable events aren't suitable for important actions that must reliably arrive, such as purchases or critical state changes.

They should be most commonly used for VFX and repeated debug logs or visualizers.

## Bindable events

Use `"BINDABLE_EVENT"` for communication within the same environment. Bindable events do not communicate between the client and server.

**IMPORTANT**: Most of the times it's better to use ModuleScripts for this with callbacks or something like [Signal](https://gist.github.com/stravant/b75a322e0919d60dde8a0316d1f09d2f), but for people that find those confusing, `BindableEvent`s are a decent option.

Register the connection:

```lua
Dysconnect.SetConnection("PlayerReady", "BINDABLE_EVENT", function(playerName: string)
    print(playerName .. " is ready!")
end)
```

Fire it from another script in the same environment:

```lua
Dysconnect.FireConnection("PlayerReady", "MyPlayer")
```

Unlike remote event firing methods, `FireConnection()` does not require a connection type argument.

## Sequential arguments and supported data types

Dysconnect lets you pass arguments sequentially instead of wrapping them in a table, like any normal event. Supported values include strings, buffers, and various Roblox data types.

For example, send several values in one event:

```lua
Dysconnect.FireAllClientConnection(
    "UpdateEffect",
    "REMOTE_EVENT",
    Vector3.new(10, 5, 20),
    Color3.fromRGB(255, 100, 50),
    CFrame.new(0, 5, 0)
)
```

Receive them in the same order:

```lua
Dysconnect.SetConnection("UpdateEffect", "REMOTE_EVENT", function(position: Vector3, color: Color3, transform: CFrame)
    print(position, color, transform)
end)
```

The callback receives the values in the order they were sent. Values that aren't officially supported by Dysconnect's optimized serialization system may fall back to JSON serialization, depending on their type.

## Connection predicates

`SetConnection()` accepts an optional predicate as its fourth argument. The callback only runs when the predicate returns `true`.

```lua
Dysconnect.SetConnection(
    "SubmitScore",
    "REMOTE_EVENT",
    function(player: Player, score: number)
        print(player.Name .. " submitted a score of " .. score)
    end,
    function(player: Player, score: number): boolean
        return score >= 0 and score <= 100000
    end
)
```

On server-side remote connections, the predicate also receives the sending `Player` as its first argument.

Predicates are useful for basic checks, but they don't replace server-side validation of important gameplay actions.

## Disconnecting a connection

`SetConnection()` returns a connection object. Call `Disconnect()` when you no longer need the callback.

```lua
local connection = Dysconnect.SetConnection("TemporaryMessage", "BINDABLE_EVENT", function(message: string)
    print(message)
end)

Dysconnect.FireConnection("TemporaryMessage", "This will be printed.")

connection:Disconnect()

Dysconnect.FireConnection("TemporaryMessage", "The disconnected callback will no longer run.")
```

You can also call `connection:Destroy()`, which is equivalent to `Disconnect()`.

## Next

See the [API reference](/api/Dysconnect) for a complete list of available methods and their parameters.
