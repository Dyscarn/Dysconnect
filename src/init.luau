--[[
	Thanks for using DysNetworking!
	Every bit of documentation is scattered through this same module.
	I tried to document it as well as I could to make it as understandable as possible.
	You'll still have to know some coding to work properly with this.
	Anyway, have fun making your games!
	
	
	
	To access this module's functions, just require it from anywhere, from any kind of script.
	For example:
	
		---CLIENT---
		const DysNetworking = require(game:GetService("ReplicatedStorage").DysNetworking)
		DysNetworking.SetConnection("EXAMPLE_1", "REMOTE_EVENT", function(param1: string)
			print(param1)
		end)
		
		DysNetworking.FireServerConnection("EXAMPLE_2", "REMOTE_EVENT", "printing from server!")
		
		---SERVER---
		const DysNetworking = require(game:GetService("ReplicatedStorage").DysNetworking)
		DysNetworking.FireAllClients("EXAMPLE_1", "REMOTE_EVENT", "printing!") --where `"printing!"` is `param1` in the client.
		--If you do `FireClient` instead, you'll have to specify the target player before anything.
		
		--When connecting from the server to a remote, the first parameter **MUST** always be the player that called the event, just like with Remote instances.
		DysNetworking.SetConnection("EXAMPLE_2", "REMOTE_EVENT", function(sourcePlayer: Player, param1: string)
			print(sourcePlayer.Name.." called this event!")
			print(param1)
		end)
		
	That's it, pretty simple.
	Everything works like your traditional Remote & Bindable instances.
	
	Though, this module will have to be initted in both sides before it can be properly used.
	For that, just create a script in `ServerScriptService` and another one in `StarterPlayerScripts` that requires it and calls `DysNetworking:Init()`.
	In the template there are two scripts that already do this and destroy themselves when they do so, so you can just use those. :p
	
	That's it! :>
]]

--!native
--!optimize 2

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const DataTypes = require("@self/DataTypes")

const ServerTimeStamp = workspace:GetAttribute("ServerTimeStamp")
const function Time(): number
	return workspace:GetServerTimeNow() - ServerTimeStamp
end

const IS_SERVER = RunService:IsServer()

--- Class used to connect the server and the clients more efficiently by encapsulating everything in a single place.
const Network = {}

const NAMING_EQUIVALENTS = table.freeze({
	REMOTE_EVENT = "RemoteEvent",
	REMOTE_FUNCTION = "RemoteFunction",
	UREMOTE_EVENT = "UnreliableRemoteEvent",
	BINDABLE_EVENT = "BindableEvent",
})
const Instances = {}

local ServiceLive = false
const Connections = {}

const DEBUG = table.freeze({
	ReceivedPackets = true,
	SentPackets = false,
	RateLimitExceeded = true,
	ExcludeUnreliable = true,
	Strict = true,
})
const EXHAUSTION_DETECTION = table.freeze({
	RateLimit = 50,
	RateDropPerSecond = 18,
	URemoteEventRateIncreaseMult = 0,
})

const PlayerExhaustionLogs = {}

const function CheckPlayerRateLimit(Player: Player, EventType: "RemoteEvent" | "RemoteFunction" | "UnreliableRemoteEvent"): boolean
	if EventType == "UnreliableRemoteEvent" and EXHAUSTION_DETECTION.URemoteEventRateIncreaseMult <= 0 then
		return true
	end

	const Now = Time()

	if not PlayerExhaustionLogs[Player.UserId] then
		PlayerExhaustionLogs[Player.UserId] = { Total = 0, Last = Now }
	end

	const Data = PlayerExhaustionLogs[Player.UserId]

	const Elapsed = Now - Data.Last
	--check how many remotes it's fired before the second passes
	const Used = Elapsed * EXHAUSTION_DETECTION.RateDropPerSecond

	Data.Total = math.max(0, Data.Total - Used)
	Data.Last = Now

	--check if it exceeds the limit
	if Data.Total >= EXHAUSTION_DETECTION.RateLimit then
		return false
	end

	Data.Total += EventType == "UnreliableRemoteEvent" and EXHAUSTION_DETECTION.URemoteEventRateIncreaseMult or 1

	return true
end

const function UnpackArgTable(ArgTable: { [any]: any }): ...any
	return table.unpack(ArgTable, 1, ArgTable.n)
end

--- Packs every argument of a fire to lower network usage when sending them.
const function PackArgumentsForNetwork(Name: string, Arguments: { any }): { any }
	if Arguments.n == 0 then
		return { Name, {} }
	end

	--calculate the total size of the buffer
	local TotalSize = 2 + #Name --1 for string length, 1 for arg length and the length itself
	const PreparedArgs = {} --param cache
	const InstanceList = {} --instance cache

	for i = 1, Arguments.n do
		const Value = Arguments[i]
		--get le tag
		const Tag = DataTypes.GetTagFromValue(Value)

		if DEBUG.Strict and Tag == DataTypes.Enum.JSON then
			warn(`[DysNetworking (DEBUG)] Data type "{typeof(Value)}" isn't officially supported by DysNetworking to auto-optimize into a buffer! Falling back to JSON strings...`)
		end

		--get le size
		const PayloadSize = DataTypes.GetPayloadSize(Tag, Value)

		--add le size to total + 1 for the tag
		TotalSize += (1 + PayloadSize)

		table.insert(PreparedArgs, {
			Tag = Tag,
			Value = Value,
			Size = PayloadSize,
		})
	end

	TotalSize = 1 + #Name
	if Arguments.n == 1 then
		TotalSize += (1 + PreparedArgs[1].Size)
	else
		TotalSize += 1
		for _, Item in PreparedArgs do
			TotalSize += (1 + Item.Size)
		end
	end

	--create the damn buffer
	const PacketBuffer = buffer.create(TotalSize)

	if Arguments.n == 1 then
		buffer.writeu8(PacketBuffer, 0, #Name + 128)
		buffer.writestring(PacketBuffer, 1, Name)
		const Offset = 1 + #Name

		buffer.writeu8(PacketBuffer, Offset, PreparedArgs[1].Tag)
		DataTypes.Writers[PreparedArgs[1].Tag](PacketBuffer, Offset + 1, PreparedArgs[1].Value, InstanceList)
	else
		buffer.writeu8(PacketBuffer, 0, #Name)
		buffer.writestring(PacketBuffer, 1, Name)
		buffer.writeu8(PacketBuffer, 1 + #Name, Arguments.n)
		local Offset = 2 + #Name

		for _, Item in PreparedArgs do
			--write le tag first
			buffer.writeu8(PacketBuffer, Offset, Item.Tag)
			--fucking write it and increment the offset based on it
			Offset = DataTypes.Writers[Item.Tag](PacketBuffer, Offset + 1, Item.Value, InstanceList)
		end
	end

	--return as a table prematurely to prevent roblox's networking from doing it itself
	return { PacketBuffer, InstanceList }
end

--- Unpacks packed arguments from a fire to use properly in a connection.
const function UnpackArgumentsFromNetwork(Arguments: { any }): (string, { [any]: any }, number, number)
	--the only argument should be the buffer
	const PacketBuffer = Arguments[1]
	const InstanceList = Arguments[2] or {}

	if typeof(PacketBuffer) == "string" then
		const Unpacked = { n = 0 }
		return PacketBuffer, Unpacked, 0, 0
	end

	--if it's not, FUCK YOU YOU DEAL WITH IT
	if typeof(PacketBuffer) ~= "buffer" then
		const Packed = table.pack(table.unpack(Arguments))
		return "", Packed, Packed.n, 0
	end

	const RawLength = buffer.readu8(PacketBuffer, 0)
	const IsSingleArg = RawLength >= 128
	const NameLength = IsSingleArg and (RawLength - 128) or RawLength

	const Name = buffer.readstring(PacketBuffer, 1, NameLength)

	local Offset: number
	local Unpacked: { any }

	if IsSingleArg then
		Unpacked = table.create(1)
		Unpacked.n = 1

		Offset = 1 + NameLength
		const Tag = buffer.readu8(PacketBuffer, Offset)
		const Value = DataTypes.Readers[Tag](PacketBuffer, Offset + 1, InstanceList)
		Unpacked[1] = Value
	else
		const ArgCount = buffer.readu8(PacketBuffer, 1 + NameLength)
		Unpacked = table.create(ArgCount)
		Unpacked.n = ArgCount

		Offset = 2 + NameLength
		--loop until the whole buffer is read
		for i = 1, ArgCount do
			--le tag
			const Tag = buffer.readu8(PacketBuffer, Offset)
			Offset += 1

			--get the shit
			const Value, NewCursor = DataTypes.Readers[Tag](PacketBuffer, Offset, InstanceList)

			--put it in the param table
			Unpacked[i] = Value
			--increase the shit
			Offset = NewCursor
		end
	end

	--FINALLY return the thing for usage
	return Name, Unpacked, Unpacked.n, #InstanceList
end

const function OnRemoteEventPacket(Player: Player?, Args: { any }, Type: "REMOTE_EVENT" | "UREMOTE_EVENT" | "BINDABLE_EVENT")
	--safety first gng
	if IS_SERVER and not Player then
		return
	end

	const Name, DecodedArgs, _ArgCount, InstanceCount = UnpackArgumentsFromNetwork(Args)

	if DEBUG.ReceivedPackets and (Type ~= "UREMOTE_EVENT" or not DEBUG.ExcludeUnreliable) then
		const BufferLength = Args[1] and typeof(Args[1]) == "buffer" and buffer.len(Args[1]) or #Name
		const NameLength = #Name
		const ArgsLength = math.max(0, BufferLength - NameLength)
		print(
			`[DysNetworking (DEBUG)] Received event of type "{Type}" with name "{Name}" and a size of {BufferLength} bytes ({NameLength} bytes for the name, {ArgsLength} bytes for the arguments{InstanceCount > 0 and `, with a total of {InstanceCount} instance{InstanceCount > 1 and "s" or ""}` or ")."}`
		)
	end

	const CallbackList = Connections[Type][Name]
	if not CallbackList then
		return
	end

	for callback, meta in CallbackList do
		const ServerCheck = Type ~= "BINDABLE_EVENT" and IS_SERVER

		if meta.Predicate then
			const Valid = if ServerCheck then meta.Predicate(Player, UnpackArgTable(DecodedArgs)) else meta.Predicate(UnpackArgTable(DecodedArgs))

			if not Valid then
				continue
			end
		end

		if ServerCheck then
			task.spawn(callback, Player, UnpackArgTable(DecodedArgs))
		else
			task.spawn(callback, UnpackArgTable(DecodedArgs))
		end
	end
end

const function OnRemoteFunctionPacket(Player: Player?, Args: { any }): any
	--safety first gng
	if IS_SERVER then
		if not Player then
			return
		end

		if not CheckPlayerRateLimit(Player) then
			if DEBUG.RateLimitExceeded then
				warn(`[DysNetworking (DEBUG)] Player "{Player.Name}" with ID "{Player.UserId}" is suspected to be exhausting the remote calls rate limit! Cancelling current remote...`)
			end

			return
		end
	end

	const Name, DecodedArgs, _ArgCount, InstanceCount = UnpackArgumentsFromNetwork(Args)

	if DEBUG.ReceivedPackets then
		const BufferLength = Args[1] and typeof(Args[1]) == "buffer" and buffer.len(Args[1]) or 0
		const NameLength = #Name
		const ArgsLength = math.max(0, BufferLength - NameLength)
		print(
			`[DysNetworking (DEBUG)] Received event of type "REMOTE_FUNCTION" with name "{Name}" and a size of {BufferLength} bytes ({NameLength} bytes for the name, {ArgsLength} bytes for the arguments{InstanceCount > 0 and `, with a total of {InstanceCount} instance{InstanceCount > 1 and "s" or ""}.` or ")."}`
		)
	end

	const Meta = Connections["REMOTE_FUNCTION"][Name]
	if not Meta then
		return
	end

	if Meta.Predicate then
		const Valid = if IS_SERVER then Meta.Predicate(Player, UnpackArgTable(DecodedArgs)) else Meta.Predicate(UnpackArgTable(DecodedArgs) :: any)

		if not Valid then
			return
		end
	end

	const Results = if IS_SERVER then table.pack(Meta.Callback(Player, UnpackArgTable(DecodedArgs))) else table.pack(Meta.Callback(UnpackArgTable(DecodedArgs) :: any))
	const CompressedResults = PackArgumentsForNetwork("", Results) --using a dummy name, ignore

	return CompressedResults
end

--- Destroys the Network instance. Only called when the server closes.
const function Destroy()
	script:ClearAllChildren()
	for _, Type in Connections do
		for EventKey, Event in Type do
			if typeof(Event) == "table" then
				for Key, _ in Event do
					Event[Key] = nil
				end
				continue
			end
			Type[EventKey] = nil
		end
	end
end

const function ServerInit()
	game:BindToClose(Destroy)

	local TypeFolder = script:FindFirstChild("Types")
	if not TypeFolder then
		TypeFolder = Instance.new("Folder")
		TypeFolder.Name = "Types"
		TypeFolder.Parent = script
	end

	for Name, InstName in NAMING_EQUIVALENTS do
		local Inst = TypeFolder:FindFirstChild(InstName)
		if not Inst then
			Inst = Instance.new(InstName)
			Inst.Name = Name
			Inst.Parent = TypeFolder
		end
		Instances[Name] = Inst

		if Name == "REMOTE_FUNCTION" then
			Inst.OnServerInvoke = OnRemoteFunctionPacket
			continue
		end

		if Name == "BINDABLE_EVENT" then
			Inst.Event:Connect(function(Args: { any })
				OnRemoteEventPacket(nil, Args, Name)
			end)

			continue
		end

		Inst.OnServerEvent:Connect(function(Player: Player, Args: { any })
			if not CheckPlayerRateLimit(Player, InstName) then
				if DEBUG.RateLimitExceeded then
					warn(`[DysNetworking (DEBUG)] Player "{Player.Name}" with ID "{Player.UserId}" is suspected to be exhausting the remote calls rate limit! Cancelling current remote...`)
				end

				return
			end

			OnRemoteEventPacket(Player, Args, Name)
		end)
	end

	Players.PlayerRemoving:Connect(function(Player: Player)
		--cleanup
		PlayerExhaustionLogs[Player.UserId] = nil
	end)
end

const function ClientInit()
	const EventFolder = script:FindFirstChild("Types") or script:WaitForChild("Types")

	for Name, _ in NAMING_EQUIVALENTS do
		Instances[Name] = EventFolder:FindFirstChild(Name) or EventFolder:WaitForChild(Name)

		if Name == "REMOTE_FUNCTION" then
			Instances[Name].OnClientInvoke = function(Args: { any }): any
				return OnRemoteFunctionPacket(nil, Args)
			end

			continue
		end

		if Name == "BINDABLE_EVENT" then
			Instances[Name].Event:Connect(function(Args: { any })
				OnRemoteEventPacket(nil, Args, Name)
			end)

			continue
		end

		Instances[Name].OnClientEvent:Connect(function(Args: { any })
			OnRemoteEventPacket(nil, Args, Name)
		end)
	end
end

--- Initializes the networking system in the current environment.
function Network.Init()
	for Name, _ in NAMING_EQUIVALENTS do
		Connections[Name] = {}
	end

	if IS_SERVER then
		ServerInit()
	else
		ClientInit()
	end

	ServiceLive = true
end

--- Adds a connection to a specific event / function instance.
--- @param name                    (`string`):      The name of the instance.
--- @param Type                    (`string`):      The type of the instance.
--- @param Callback                (`function`):    The code that will run when the connection is fired.
--- @return `RBXScriptConnection`                   The set connection for further usage in the script from where this is called.
function Network.SetConnection(
	name: string,
	Type: "REMOTE_EVENT" | "UREMOTE_EVENT" | "REMOTE_FUNCTION" | "BINDABLE_EVENT",
	Callback: (...any) -> ...any,
	Predicate: ((...any) -> boolean)?
): RBXScriptConnection
	if #name > 127 then
		warn(`[DysNetworking:SetConnection()] Can't assign connection with name "{name}" because it's too long! Try to shorten it a bit.`)
		return
	end

	Network.WaitForInit()

	if Connections[Type][name] == nil and Type ~= "REMOTE_FUNCTION" then
		Connections[Type][name] = {}
	end
	if Type == "REMOTE_FUNCTION" then
		Connections[Type][name] = {
			Callback = Callback,
			Predicate = Predicate,
		}
	else
		Connections[Type][name][Callback] = {
			Predicate = Predicate,
		}
	end

	return {
		Connected = true,
		Disconnect = function(Connection)
			Connections[Type][name][Callback] = nil
			Connection.Connected = false
		end,
		Destroy = function(Connection)
			Connection:Disconnect()
		end,
	}
end

--- Fires a specific client's event / function connections.
--- @param target  (`Player`):  The target client whose connections will be fired.
--- @param name    (`string`):  The name of the desired event / function
--- @param Type    (`string`):  The type of instance to fire the connections of
--- @param ...                  Any parameters to pass to the connection
function Network.FireClientConnection(target: Player | { Player }, name: string, Type: "REMOTE_EVENT" | "UREMOTE_EVENT" | "REMOTE_FUNCTION", ...): any | nil
	if not target then
		warn(`[DysNetworking:FireClientConnection()] No target(s) for the event was/were provided!`, debug.traceback())
		return
	end

	if not name then
		warn(`[DysNetworking:FireClientConnection()] No name was provided for the event!`, debug.traceback())
		return
	end

	if #name > 127 then
		warn(`[DysNetworking:FireClientConnection()] Can't fire connection with name "{name}" because it's too long! Try to shorten it a bit.`)
		return
	end

	Network.WaitForInit()

	if not IS_SERVER then
		warn("[DysNetworking:FireClientConnection()] This function shouldn't be called from the client. Make sure that it isn't!", debug.traceback())
		return
	end

	const event = Instances[Type]
	if not event then
		warn(`[DysNetworking:FireClientConnection()] Event {name} couldn't be fired because it doesn't exist! Are you sure you're spelling the type correctly? ({Type})`, debug.traceback())
		return
	end

	const Arguments = table.pack(...)
	const CompressedArguments = PackArgumentsForNetwork(name, Arguments)

	const function Fire(player: Player, ...)
		if DEBUG.SentPackets then
			print(`[DysNetworking (DEBUG)] Fired event of type "{Type}" with name "{name}".\n{debug.traceback()}`)
		end

		if Type == "REMOTE_FUNCTION" then
			const Results = event:InvokeClient(player, ...)

			if DEBUG.ReceivedPackets then
				const BufferLength = Results[1] and typeof(Results[1]) == "buffer" and buffer.len(Results[1]) or 0
				print(`[DysNetworking (DEBUG)] Received back results from a "REMOTE_FUNCTION" with name "{name}" and a size of {BufferLength} bytes.`)
			end

			const _, DecompressedResults, ArgCount = UnpackArgumentsFromNetwork(Results)
			return UnpackArgTable(DecompressedResults, ArgCount)
		else
			event:FireClient(player, ...)
		end
		return
	end

	if typeof(target) == "table" then
		const Results = {}
		for _, player: Player in target do
			Results[player.UserId] = table.pack(Fire(player, CompressedArguments))
		end
		return Results
	end

	return Fire(target, CompressedArguments)
end

--- Fires an event's connections to every single connected client. If the type of the object is a RemoteFunction, it won't do anything.
--- @param name    (`string`):  The name of the desired event
--- @param Type    (`string`):  The type of the event (Reliable / Unreliable)
--- @param ...                  Any parameters to pass to the connection
function Network.FireAllClientConnection(name: string, Type: "REMOTE_EVENT" | "UREMOTE_EVENT", ...)
	if not name then
		warn(`[DysNetworking:FireAllClientConnection()] No name was provided for the event!`, debug.traceback())
		return
	end

	if #name > 127 then
		warn(`[DysNetworking:FireAllClientConnection()] Can't fire connection with name "{name}" because it's too long! Try to shorten it a bit.`, debug.traceback())
		return
	end

	Network.WaitForInit()

	if not IS_SERVER then
		warn("[DysNetworking:FireAllClientConnection()] This function shouldn't be called from the client. Make sure that it isn't!", debug.traceback())
		return
	end

	if Type == "REMOTE_FUNCTION" or Type == "BINDABLE_EVENT" then
		warn(`[DysNetworking:FireAllClientConnection()] Event of type {Type} cannot be fired to every client at once!`, debug.traceback())
		return
	end

	const instance = Instances[Type]
	if not instance then
		warn(`[DysNetworking:FireAllClientConnection()] Event {name} couldn't be fired because it doesn't exist! Are you sure you're connecting it to anything?`, debug.traceback())
		return
	end

	const Arguments = table.pack(...)
	const CompressedArguments = PackArgumentsForNetwork(name, Arguments)

	if DEBUG.SentPackets then
		print(`[DysNetworking (DEBUG)] Fired event of type "{Type}" with name "{name}".\n{debug.traceback()}`)
	end

	instance:FireAllClients(CompressedArguments)
end

--- Fires a server's event / function connections.
--- @param name    (`string`):  The name of the desired event / function
--- @param Type    (`string`):  The type of instance to fire the connections of
--- @param ...                  Any parameters to pass to the connection
function Network.FireServerConnection(name: string, Type: "REMOTE_EVENT" | "UREMOTE_EVENT" | "REMOTE_FUNCTION", ...): any | nil
	if not name then
		warn(`[DysNetworking:FireServerConnection()] No name was provided for the event!`, debug.traceback())
		return
	end

	if #name > 127 then
		warn(`[DysNetworking:FireServerConnection()] Can't fire connection with name "{name}" because it's too long! Try to shorten it a bit.`)
		return
	end

	Network.WaitForInit()

	if IS_SERVER then
		warn("[DysNetworking:FireServerConnection()] This function shouldn't be called from the server. Make sure that it isn't!", debug.traceback())
		return
	end

	const instance = Instances[Type]
	if not instance then
		warn(`[DysNetworking:FireServerConnection()] Event {name} couldn't be fired because it doesn't exist! Are you sure you're spelling the type correctly? ({Type})`, debug.traceback())
		return
	end

	const Arguments = table.pack(...)
	const CompressedArguments = PackArgumentsForNetwork(name, Arguments)

	if DEBUG.SentPackets then
		print(`[DysNetworking (DEBUG)] Fired event of type "{Type}" with name "{name}".\n{debug.traceback()}`)
	end

	if Type == "REMOTE_FUNCTION" then
		const Results = instance:InvokeServer(CompressedArguments)

		if DEBUG.ReceivedPackets then
			const BufferLength = Results[1] and typeof(Results[1]) == "buffer" and buffer.len(Results[1]) or 0
			print(`[DysNetworking (DEBUG)] Received back results from a "REMOTE_FUNCTION" with name "{name}" and a size of {BufferLength} bytes.`)
		end

		const _, DecompressedResults, ArgCount = UnpackArgumentsFromNetwork(Results)
		return UnpackArgTable(DecompressedResults, ArgCount)
	end

	instance:FireServer(CompressedArguments)

	return
end

--- Fires a BindableEvent's connections
--- @param name (`string`): The name of the desired BindableEvent
--- @param ...              Any parameters to pass to the connection
function Network.FireConnection(name: string, ...)
	if not name then
		warn(`[DysNetworking:FireConnection()] No name was provided for the event!`, debug.traceback())
		return
	end

	if #name > 127 then
		warn(`[DysNetworking:FireConnection()] Can't fire connection with name "{name}" because it's too long! Try to shorten it a bit.`)
		return
	end

	Network.WaitForInit()

	const Bindable = Instances["BINDABLE_EVENT"]
	if not Bindable then
		warn(
			`[DysNetworking:FireServerConnection()] Event {name} couldn't be fired because the main BindableEvent instance is missing! Are you sure the module is initializing properly?`,
			debug.traceback()
		)
		return
	end

	const Arguments = table.pack(...)
	const CompressedArguments = PackArgumentsForNetwork(name, Arguments)

	if DEBUG.SentPackets then
		print(`[DysNetworking (DEBUG)] Fired event of type "BINDABLE_EVENT" with name "{name}".\n{debug.traceback()}`)
	end

	Bindable:Fire(CompressedArguments)
end

--- Waits until the networking service is live for usage.
---
--- Should only be used internally.
function Network.WaitForInit()
	while not ServiceLive do
		task.wait()
	end
end

--- Checks if the Network service is available in the current environment
function Network.IsLive()
	return ServiceLive
end

return table.freeze(Network)
