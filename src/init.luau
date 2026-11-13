--[[
	Thanks for using Dysconnect!
	Every bit of documentation is scattered through this same module.
	I tried to document it as well as I could to make it as understandable as possible.
	You'll still have to know some coding to work properly with this.
	Anyway, have fun making your games!
	
	
	
	To access this module's functions, just require it from anywhere, from any kind of script.
	For example:
	
		---CLIENT---
		const Dysconnect = require(game:GetService("ReplicatedStorage").Dysconnect)
		Dysconnect.SetConnection("EXAMPLE_1", "REMOTE_EVENT", function(param1: string)
			print(param1)
		end)
		
		Dysconnect.FireServerConnection("EXAMPLE_2", "REMOTE_EVENT", "printing from server!")
		
		---SERVER---
		const Dysconnect = require(game:GetService("ReplicatedStorage").Dysconnect)
		Dysconnect.FireAllClients("EXAMPLE_1", "REMOTE_EVENT", "printing!") --where `"printing!"` is `param1` in the client.
		--If you do `FireClient` instead, you'll have to specify the target player before anything.
		
		--When connecting from the server to a remote, the first parameter **MUST** always be the player that called the event, just like with Remote instances.
		Dysconnect.SetConnection("EXAMPLE_2", "REMOTE_EVENT", function(sourcePlayer: Player, param1: string)
			print(sourcePlayer.Name.." called this event!")
			print(param1)
		end)
		
	That's it, pretty simple.
	Everything works like your traditional Remote & Bindable instances.
	
	Though, this module will have to be initted in both sides before it can be properly used.
	For that, just create a script in `ServerScriptService` and another one in `StarterPlayerScripts` that requires it and calls `Dysconnect.Init()`.
	
	That's it! :>
]]

--!strict
--!native
--!optimize 2

--[[
	The type checking in this module is actually pretty damn messy.
	It's one of the first times I use strict typing in a serious way,
	and complying with everything it says is hard. :(
	
	I'll look into improving typing here in the future.
	
	-dys
]]

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const DataTypes = require("@self/DataTypes")

local ServerTimeStamp: number?
const function Time(): number
	return workspace:GetServerTimeNow() - (ServerTimeStamp :: number)
end

const IS_SERVER = RunService:IsServer()

--[=[
	@type Callback ((...any) -> any?) | ((Player: Player, ...any) -> any?)
	@within Dysconnect
]=]
type Callback = ((...any) -> any?) | ((Player: Player, ...any) -> any?)
--[=[
	@type Predicate ((...any) -> boolean) | ((Player: Player, ...any) -> boolean)
	@within Dysconnect
	
	Function containing sanity checks to execute a callback afterwards if it returns `true`.
]=]
type Predicate = ((...any) -> boolean) | ((Player: Player, ...any) -> boolean)

--[=[
	@type RemoteType "REMOTE_EVENT" | "UREMOTE_EVENT"
	@within Dysconnect
	
	Event types that go over the network and don't return anything.
]=]
type RemoteType = "REMOTE_EVENT" | "UREMOTE_EVENT"
--[=[
	@type NetworkEventType RemoteType | "BINDABLE_EVENT"
	@within Dysconnect
	
	Event types that do and don't go over the network but don't return anything.
]=]
type NetworkEventType = RemoteType | "BINDABLE_EVENT"
--[=[
	@type InvokableType RemoteType | "REMOTE_FUNCTION"
	@within Dysconnect
	
	Event types that go over the network that do and don't return anything.
]=]
type InvokableType = RemoteType | "REMOTE_FUNCTION"
--[=[
	@type EventType RemoteType | NetworkEventType | InvokableType
	@within Dysconnect
	
	All supported event and function types in Dysconnect.
]=]
type EventType = RemoteType | NetworkEventType | InvokableType

const Connections = {} :: {
	[EventType]: {
		[string]: {
			Callback: Callback?,
			Predicate: Predicate?,
			[Callback]: {
				Predicate: Predicate?,
			}?,
		},
	},
}

--[=[
	@class Connection
	@__index Connection
	
	Represents a connection to a network event or function.
]=]
const Connection = {}
Connection.__index = Connection

--[=[
	@interface Connection
	@within Connection
	
	.Connected boolean -- If this [Connection] is still bound to its event.
	.Type EventType -- The type of event it's connected to.
	.Name string -- The name of the event it's connected to.
	.Callback Callback -- The callback that'll execute when this connection receives a signal.
]=]
type Connection = typeof(setmetatable(
	{} :: {
		Connected: boolean,
		Type: EventType,
		Name: string,
		Callback: Callback,
	},
	{} :: {
		Disconnect: (self: Connection) -> (),
		Destroy: (self: Connection) -> (),
	}
))

--[=[
	@within Connection
	
	Destroys this [Connection], rendering it unusuable and setting its [Connection.Connected] property to `false`.
]=]
function Connection.Disconnect(self: Connection)
	Connections[self.Type][self.Name][self.Callback] = nil
	table.clear(self)
	self.Connected = false
	setmetatable(self, nil)
end
--[=[
	@function Destroy
	@within Connection
	
	Equivalent to [Connection.Disconnect].
	
	@param self Connection
]=]
Connection.Destroy = Connection.Disconnect --shortcut for compatibility

--[=[
	@class Dysconnect
	
	Class used to connect the server and the clients more efficiently by encapsulating everything in a single place.
]=]
const Dysconnect = {}

const NAMING_EQUIVALENTS = table.freeze({
	REMOTE_EVENT = "RemoteEvent",
	REMOTE_FUNCTION = "RemoteFunction",
	UREMOTE_EVENT = "UnreliableRemoteEvent",
	BINDABLE_EVENT = "BindableEvent",
}) :: typeof(table.freeze({} :: { [EventType]: string }))
const Instances = {} :: { [EventType]: Instance }

--[=[
	@interface BatchPacket
	@within Dysconnect
	@private
	
	Queued packet for batching in a frame.
	
	.EventName string -- The name of the target event.
	.Args { [number]: any } -- The arguments to pass to the event.
]=]
type BatchPacket = {
	EventName: string,
	Args: Args,
}
--[=[
	@interface TargetedBatchPacket
	@within Dysconnect
	@private
	
	Queued packet for batching in a frame, targeted to one or more [Player]s.
	
	.Base BatchPacket -- Contains all fields from [BatchPacket]. This doesn't mean this has a field called "Base".
	.EventType RemoteType -- The type of event to fire.
	.Target (Player | { Player })? -- The player/s to fire the event to.
]=]
type TargetedBatchPacket = BatchPacket & {
	Target: (Player | "All")?,
	EventType: RemoteType,
}
type ReceivedBatchPacket = BatchPacket

const BatchQueue = {} :: { TargetedBatchPacket }

local ServiceLive = false

--[=[
	@interface FireOptions
	@within Dysconnect
	
	Options for a specific remote call.
	
	.Batch boolean? -- If this remote call will be batch. Overrides [BATCHING.BatchByDefault].
]=]
type FireOptions = {
	Batch: boolean?,
}
type BuiltFireOptions = FireOptions & {
	__DysconnectFireOptions: true,
}
--[=[
	@within Dysconnect
	
	Makes a [FireOptions] table for usage in a remote call
	This should be used instead of directly making a table as this adds a custom header to identify
	that these are [FireOptions].
	
	@param Options FireOptions -- The options to apply to it.
	@return FireOptions -- The [FireOptions] to use, with a custom header.
]=]
function Dysconnect.FireOptions(Options: FireOptions): typeof(table.freeze({} :: BuiltFireOptions))
	--type casting it here so i don't have to make a different table for it while keeping it strict
	(Options :: BuiltFireOptions).__DysconnectFireOptions = true
	return table.freeze(Options)
end

--[=[
	@interface DEBUG
	@within Dysconnect
	@private
	
	Debug print statement toggles.
	
	Modifiable in the network script or in [Dysconnect.Init].	
	
	.QueuedPackets boolean -- Prints info whenever a packet is added to the batch queue (including name, type and size in bytes).
	.ReceivedPackets boolean -- Prints info whenever a packet is received on either side (including name, type and size in bytes).
	.SentPackets boolean -- Prints info whenever a packet is sent from either side (including name and type).
	.RateLimitExceeded boolean -- Prints info whenever a [Player] exceeds its rate limit, thus dropping the packets it sends (includes name and [Player.UserId]).
	.ExcludeUnreliable boolean -- If `true`, will exclude [UnreliableRemoteEvent] send & receive prints (from [DEBUG.ReceivedPackets] and [DEBUG.SentPackets]).
	.Strict boolean -- Prints a warn if an object of a type not supported by Dysconnect is trying to be sent over the network, falling back to JSON.
]=]
local DEBUG = table.freeze({
	QueuedPackets = true,
	ReceivedPackets = true,
	SentPackets = false,
	RateLimitExceeded = true,
	ExcludeUnreliable = true,
	Strict = true,
})
--[=[
	@interface EXHAUSTION_DETECTION
	@within Dysconnect
	@private
	
	Configuration for per-player network exhaustion detection.
	Tracks incoming remote calls and gradually reduces the accumulated
	usage over time to limit excessive requests.
	
	Modifiable in the network script or in [Dysconnect.Init].
	
	.RateLimit number -- Maximum accumulated usage before requests are rejected.
	.RateDropPerSecond number -- Rate at which accumulated usage decays per second.
	.URemoteEventRateIncreaseMult number -- Amount of usage added by each [UnreliableRemoteEvent] call.
]=]
local EXHAUSTION_DETECTION = table.freeze({
	RateLimit = 50,
	RateDropPerSecond = 18,
	URemoteEventRateIncreaseMult = 0,
})
--[=[
	@interface BATCHING
	@within Dysconnect
	@private
	
	Configuration for event batching, to not fire a lot of remote calls in a single frame.
	Limited at a batch size cap in KB to not produce lag spikes every time a big event
	with a lot of remote calls fires in a single frame, equivalent to firing a LOT of remotes
	in the same timespan, which is an issue.
	
	Modifiable in the network script or in [Dysconnect.Init].
	
	.BatchByDefault boolean -- If remote calls will be batched by default, since you might not want this sometimes.
	.MaxBatchSize number -- The maximum packet size of a single frame's batch, in KB.
]=]
local BATCHING = table.freeze({
	BatchByDefault = true,
	MaxBatchSize = 16, --KB
})

const function WriteMissingTableValues<T, S>(Target: T & {}, Values: S & {}): T & S & {}
	for Key, Value in Values :: { [any]: any } do
		if Target[Key] ~= nil then
			continue
		end

		Target[Key] = Value
	end

	return Target
end

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

const function ExtractFireOptions(Args: { [any]: any }): (boolean, Args?)
	const n = Args.n :: number
	if not n or n <= 0 then
		return BATCHING.BatchByDefault, Args
	end

	const options = Args[n] :: BuiltFireOptions
	if typeof(options) ~= "table" or not options.__DysconnectFireOptions then
		return BATCHING.BatchByDefault, Args
	end

	const batch: boolean = if options.Batch ~= nil then options.Batch else BATCHING.BatchByDefault

	if not batch then
		return false, nil
	end

	--this seems like an unnecessary first approach
	-- const Clean = table.create(n - 1)
	-- for i = 1, n - 1 do
	-- 	Clean[i] = Args[i]
	-- end
	const Clean = table.clone(Args)
	Clean[n] = nil
	return true, Clean
end

type Args = {
	n: number,
	[number]: any,
}
const function PackArgumentsForNetwork(Name: string, Arguments: Args): { any }
	if Arguments.n == 0 then
		return { Name, {} }
	end

	--calculate the total size of the buffer
	local TotalSize = 2 + #Name --1 for string length, 1 for arg length and the length itself
	const PreparedArgs = {} :: {
		{
			Tag: number,
			Value: any,
			Size: number,
		}
	} --param cache
	const InstanceList = {} --instance cache

	for i = 1, Arguments.n do
		const Value = Arguments[i]
		--get le tag
		const Tag = DataTypes.GetTagFromValue(Value)

		if DEBUG.Strict and Tag == DataTypes.Enum.JSON then
			warn(`[Dysconnect (DEBUG)] Data type "{typeof(Value)}" isn't officially supported by Dysconnect to auto-optimize into a buffer! Falling back to JSON strings...`)
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

	--create the buffer
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

const function UnpackArgumentsFromNetwork(Arguments: { any }): (string, { [any]: any }, number, number)
	--the only argument should be the buffer
	const PacketBuffer = Arguments[1]
	const InstanceList = Arguments[2] or {}

	if typeof(PacketBuffer) == "string" then
		const Unpacked = { n = 0 }
		return PacketBuffer, Unpacked, 0, 0
	end

	--if it's not, halt, supposing it's already unpacked
	if typeof(PacketBuffer) ~= "buffer" then
		const Packed = table.pack(table.unpack(Arguments))
		return "", Packed, Packed.n, 0
	end

	const RawLength = buffer.readu8(PacketBuffer, 0)
	const IsSingleArg = RawLength >= 128
	const NameLength = IsSingleArg and (RawLength - 128) or RawLength

	const Name = buffer.readstring(PacketBuffer, 1, NameLength)

	local Offset: number
	local Unpacked: Args

	if IsSingleArg then
		Unpacked = table.create(1) :: Args
		Unpacked.n = 1

		Offset = 1 + NameLength
		const Tag = buffer.readu8(PacketBuffer, Offset)
		const Value = DataTypes.Readers[Tag](PacketBuffer, Offset + 1, InstanceList)
		Unpacked[1] = Value
	else
		const ArgCount = buffer.readu8(PacketBuffer, 1 + NameLength)
		Unpacked = table.create(ArgCount) :: Args
		Unpacked.n = ArgCount

		Offset = 2 + NameLength
		--loop until the whole buffer is read
		for i = 1, ArgCount do
			--le tag
			const Tag = buffer.readu8(PacketBuffer, Offset)
			Offset += 1

			--get correspondent value
			const Value, NewCursor = DataTypes.Readers[Tag](PacketBuffer, Offset, InstanceList)

			--put it in the param table
			Unpacked[i] = Value
			--increase pointer
			Offset = NewCursor
		end
	end

	--FINALLY return the thing for usage
	return Name, Unpacked, Unpacked.n, #InstanceList
end

const function Fire(player: Player, event: RemoteEvent | UnreliableRemoteEvent | RemoteFunction, name: string, Type: InvokableType, ...): ...any
	if DEBUG.SentPackets then
		print(`[Dysconnect (DEBUG)] Fired event of type "{Type}" with name "{name}".\n{debug.traceback()}`)
	end

	if Type == "REMOTE_FUNCTION" then
		const Results = (event :: RemoteFunction):InvokeClient(player, ...)

		if DEBUG.ReceivedPackets then
			const BufferLength = Results[1] and typeof(Results[1]) == "buffer" and buffer.len(Results[1]) or 0
			print(`[Dysconnect (DEBUG)] Received back results from a "REMOTE_FUNCTION" with name "{name}" and a size of {BufferLength} bytes.`)
		end

		const _, DecompressedResults, ArgCount = UnpackArgumentsFromNetwork(Results)
		return UnpackArgTable(DecompressedResults, ArgCount)
	else
		(event :: RemoteEvent --[[ | UnreliableRemoteEvent ]]):FireClient(player, ...)
	end
	return
end

const function PackBatchEnvelope(Entries: { BatchPacket }): (buffer, { Instance })
	const EntryCount = #Entries
	local TotalSize = 4

	const InstanceList = {} :: { Instance }
	const InstanceMap = {} :: { [Instance]: number }

	const Prepared = {} :: {
		{
			Name: string,
			Args: { { Tag: number, Value: any, Size: number } },
			Size: number,
			Offset: number,
		}
	}

	for _, Entry in Entries do
		TotalSize += 4 + #Entry.EventName

		const EntryArgs = {} :: { { Tag: number, Value: any, Size: number } }
		local EntrySize = 0

		for i = 1, Entry.Args.n do
			const Value = Entry.Args[i]
			const Tag = DataTypes.GetTagFromValue(Value)

			if Tag == DataTypes.Enum.Instance then
				if not InstanceMap[Value] then
					table.insert(InstanceList, Value)
					InstanceMap[Value] = #InstanceList
				end
			end

			const PayloadSize = DataTypes.GetPayloadSize(Tag, Value)
			EntrySize += 1 + PayloadSize

			table.insert(EntryArgs, {
				Tag = Tag,
				Value = Value,
				Size = PayloadSize,
			})
		end

		TotalSize += EntrySize

		table.insert(Prepared, {
			Name = Entry.EventName,
			Args = EntryArgs,
			Size = EntrySize,
			Offset = 0,
		})
	end

	const Buffer = buffer.create(TotalSize)
	local Offset = 0

	buffer.writeu16(Buffer, Offset, EntryCount)
	Offset += 2
	buffer.writeu16(Buffer, Offset, #InstanceList)
	Offset += 2

	for _, Payload in Prepared do
		Payload.Offset = Offset

		buffer.writeu8(Buffer, Offset, #Payload.Name)
		Offset += 1
		buffer.writestring(Buffer, Offset, Payload.Name)
		Offset += #Payload.Name

		buffer.writeu8(Buffer, Offset, #Payload.Args)
		Offset += 1

		buffer.writeu16(Buffer, Offset, Payload.Size)
		Offset += 2

		for _, Arg in Payload.Args do
			buffer.writeu8(Buffer, Offset, Arg.Tag)
			Offset += 1
			Offset = DataTypes.Writers[Arg.Tag](Buffer, Offset, Arg.Value, InstanceList)
		end
	end

	return Buffer, InstanceList
end

const function UnpackBatchEnvelope(Buffer: buffer, InstanceList: { Instance }): { ReceivedBatchPacket }
	local Offset = 0

	const EntryCount = buffer.readu16(Buffer, Offset)
	Offset += 2
	const _InstanceCount = buffer.readu16(Buffer, Offset)
	Offset += 2

	const Entries = {} :: { ReceivedBatchPacket }

	for _ = 1, EntryCount do
		const NameLength = buffer.readu8(Buffer, Offset)
		Offset += 1
		const Name = buffer.readstring(Buffer, Offset, NameLength)
		Offset += NameLength

		const ArgCount = buffer.readu8(Buffer, Offset)
		Offset += 1
		const EntrySize = buffer.readu16(Buffer, Offset)
		Offset += 2

		const Args = table.create(ArgCount) :: Args
		Args.n = ArgCount

		for i = 1, ArgCount do
			const Tag = buffer.readu8(Buffer, Offset)
			Offset += 1
			const Value, NewOffset = DataTypes.Readers[Tag](Buffer, Offset, InstanceList)
			Args[i] = Value
			Offset = NewOffset
		end

		table.insert(Entries, {
			EventName = Name,
			EventType = nil,
			Args = Args,
			Size = EntrySize,
		})
	end

	return Entries
end

const function ReceiveCall(Player: Player?, name: string, Type: NetworkEventType, ...)
	const CallbackList = Connections[Type][name]
	if not CallbackList then
		return
	end

	for callback, meta in CallbackList do
		const ServerCheck = Type ~= "BINDABLE_EVENT" and IS_SERVER

		if meta.Predicate then
			const Valid = if ServerCheck then (meta.Predicate :: (Player: Player, ...any) -> boolean)(Player :: Player, ...) else (meta.Predicate :: (...any) -> boolean)(...)

			if not Valid then
				continue
			end
		end

		if ServerCheck then
			task.spawn(callback, Player :: Player, ...)
		else
			task.spawn(callback, ...)
		end
	end
end

const function GetSizeOfBatchEvent(name: string, Args: Args): number
	local Size = 4 + #name
	for i = 1, Args.n do
		const Arg = Args[i]
		-- + 1 for tag
		Size += 1 + DataTypes.GetPayloadSize(DataTypes.GetTagFromValue(Arg), Arg)
	end
	return Size
end

const function FireQueuedCalls()
	if #BatchQueue == 0 then
		return
	end

	const SelectedCalls = {
		REMOTE_EVENT = {},
		UREMOTE_EVENT = {},
	} :: { [RemoteType]: { [Player | "All" | "Server"]: { BatchPacket } } }
	local AccumulatedSizes = {
		REMOTE_EVENT = {},
		UREMOTE_EVENT = {},
	} :: { [RemoteType]: { [Player | "All" | "Server"]: number } }
	const IndexesToRemove = {} :: { number }
	for Index, Event in BatchQueue do
		const BufferLength = GetSizeOfBatchEvent(Event.EventName, Event.Args)
		const EventType = Event.EventType
		const EventTarget = Event.Target or "Server"

		const ExistingAccumulated = AccumulatedSizes[EventType][EventTarget]
		if ExistingAccumulated and ExistingAccumulated > BATCHING.MaxBatchSize then
			continue
		end

		const Size = BufferLength / 1024
		--if the size of the call args is already bigger than the max limit, just send it immediately
		if Size >= BATCHING.MaxBatchSize then
			--only remove it from queue if it's bigger than the cap or if it's sent
			table.insert(IndexesToRemove, Index)
			-- gotta add FireOptions here so it doesn't try to batch it again at all,
			-- which would make an infinite loop of doom and despair
			const Options = Dysconnect.FireOptions({ Batch = false })
			if Event.Target == "Server" then
				if not IS_SERVER then
					Dysconnect.FireServerConnection(Event.EventName, EventType, table.unpack(Event.Args), Options)
				end
			elseif IS_SERVER then
				if Event.Target == "All" then
					Dysconnect.FireAllClientConnection(Event.EventName, EventType, table.unpack(Event.Args), Options)
				else
					Dysconnect.FireClientConnection(EventTarget :: Player, Event.EventName, EventType, table.unpack(Event.Args), Options)
				end
			end
			continue
		end
		--if adding the event would exceed the cap, but the event isn't bigger than or as big as the cap, skip it
		if ExistingAccumulated and ExistingAccumulated + Size > BATCHING.MaxBatchSize then
			continue
		end

		--only remove it from queue if it's bigger than the cap or if it's sent
		table.insert(IndexesToRemove, Index)
		if ExistingAccumulated == nil then
			AccumulatedSizes[EventType][EventTarget] = BufferLength / 1024
		else
			AccumulatedSizes[EventType][EventTarget] += BufferLength / 1024
		end

		const Calls = SelectedCalls[EventType]
		local CallGroup: { BatchPacket }
		if Calls[EventTarget] == nil then
			Calls[EventTarget] = {}
		end
		CallGroup = Calls[EventTarget]
		table.insert(CallGroup, Event :: BatchPacket)
	end
	for index = #IndexesToRemove, 1, -1 do
		table.remove(BatchQueue, IndexesToRemove[index])
	end
	table.clear(IndexesToRemove)

	for _, Group in AccumulatedSizes do --clean this, why not?
		table.clear(Group)
	end
	table.clear(AccumulatedSizes)

	for Type, CallGroup in SelectedCalls do
		const event = Instances[Type] :: RemoteEvent --[[ | UnreliableRemoteEvent ]]
		if not event then
			continue
		end

		for Target, Events in CallGroup do
			const EnvelopeBuffer, InstanceList = PackBatchEnvelope(Events)
			-- Compressing it like this will add slight but negligible overhead
			-- because of an attempt to serialize InstanceList and failing,
			-- but it's not like i care enough to change it.
			-- -dys
			const Compressed = PackArgumentsForNetwork("__Batch", table.pack(EnvelopeBuffer, InstanceList))

			if Target == "All" then
				event:FireAllClients(Compressed)
			elseif Target == "Server" then
				event:FireServer(Compressed)
			else
				event:FireClient(Target, Compressed)
			end
		end
	end
end

const function OnRemoteEventPacket(Player: Player?, Args: { any }, Type: NetworkEventType)
	--safety first gng
	if IS_SERVER and not Player then
		return
	end

	const Name, DecodedArgs, _ArgCount, InstanceCount = UnpackArgumentsFromNetwork(Args)

	if Name == "__Batch" then
		if DEBUG.ReceivedPackets and (Type ~= "UREMOTE_EVENT" or not DEBUG.ExcludeUnreliable) then
			const BufferLength = Args[1] and typeof(Args[1]) == "buffer" and buffer.len(Args[1]) or #Name
			print(
				`[Dysconnect (DEBUG)] Received event batch of type "{Type}" and a size of {BufferLength} bytes{InstanceCount > 0 and `, with a total of {InstanceCount} instance{InstanceCount > 1 and "s" or ""}.` or "."}`
			)
		end

		const Entries = UnpackBatchEnvelope(DecodedArgs[1], DecodedArgs[2] or {})

		for _, Entry in Entries do
			if DEBUG.ReceivedPackets and (Type ~= "UREMOTE_EVENT" or not DEBUG.ExcludeUnreliable) then
				const BufferLength = GetSizeOfBatchEvent(Entry.EventName, Entry.Args)
				const NameLength = #Entry.EventName
				const ArgsLength = math.max(0, BufferLength - NameLength)
				print(
					`[Dysconnect (DEBUG)] Received batched event of type "{Type}" with name "{Entry.EventName}" and a size of {BufferLength} bytes ({NameLength} bytes for the name, {ArgsLength} bytes for the arguments{InstanceCount > 0 and `, with a total of {InstanceCount} instance{InstanceCount > 1 and "s" or ""}.` or ")."}`
				)
			end

			ReceiveCall(Player, Entry.EventName, Type, UnpackArgTable(Entry.Args))
		end

		return
	end

	if DEBUG.ReceivedPackets and (Type ~= "UREMOTE_EVENT" or not DEBUG.ExcludeUnreliable) then
		const BufferLength = Args[1] and typeof(Args[1]) == "buffer" and buffer.len(Args[1]) or #Name
		const NameLength = #Name
		const ArgsLength = math.max(0, BufferLength - NameLength)
		print(
			`[Dysconnect (DEBUG)] Received event of type "{Type}" with name "{Name}" and a size of {BufferLength} bytes ({NameLength} bytes for the name, {ArgsLength} bytes for the arguments{InstanceCount > 0 and `, with a total of {InstanceCount} instance{InstanceCount > 1 and "s" or ""}.` or ")."}`
		)
	end

	ReceiveCall(Player, Name, Type, UnpackArgTable(DecodedArgs))
end

const function OnRemoteFunctionPacket(Player: Player?, Args: { any }): any
	--safety first gng
	if IS_SERVER then
		if not Player then
			return
		end

		if not CheckPlayerRateLimit(Player, "RemoteFunction") then
			if DEBUG.RateLimitExceeded then
				warn(`[Dysconnect (DEBUG)] Player "{Player.Name}" with ID "{Player.UserId}" is suspected to be exhausting the remote calls rate limit! Cancelling current remote...`)
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
			`[Dysconnect (DEBUG)] Received event of type "REMOTE_FUNCTION" with name "{Name}" and a size of {BufferLength} bytes ({NameLength} bytes for the name, {ArgsLength} bytes for the arguments{InstanceCount > 0 and `, with a total of {InstanceCount} instance{InstanceCount > 1 and "s" or ""}.` or ")."}`
		)
	end

	const Meta = Connections["REMOTE_FUNCTION"][Name]
	if not Meta then
		return
	end

	if Meta.Predicate then
		const Valid = if IS_SERVER
			then (Meta.Predicate :: (Player: Player, ...any) -> boolean)(Player :: Player, UnpackArgTable(DecodedArgs))
			else (Meta.Predicate :: (...any) -> boolean)(UnpackArgTable(DecodedArgs) :: any)

		if not Valid then
			return
		end
	end

	-- const Results = if IS_SERVER then table.pack(Meta.Callback(Player, UnpackArgTable(DecodedArgs))) else table.pack(Meta.Callback(UnpackArgTable(DecodedArgs) :: any))
	const Results = table.pack(
		if IS_SERVER then (Meta.Callback :: (Player: Player, ...any) -> ())(Player :: Player, UnpackArgTable(DecodedArgs)) else (Meta.Callback :: (...any) -> ())(UnpackArgTable(DecodedArgs))
	)
	const CompressedResults = PackArgumentsForNetwork("", Results) --using a dummy name, ignore

	return CompressedResults
end

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
	ServerTimeStamp = workspace:GetServerTimeNow()
	game:BindToClose(Destroy)

	local TypeFolder = script:FindFirstChild("Types") :: Folder
	if not TypeFolder then
		TypeFolder = Instance.new("Folder")
		TypeFolder.Name = "Types"
		TypeFolder.Parent = script
	end

	for Name, InstName in NAMING_EQUIVALENTS do
		local Inst = TypeFolder:FindFirstChild(InstName) :: Instance
		if not Inst then
			Inst = Instance.new(InstName)
			Inst.Name = Name
			Inst.Parent = TypeFolder
		end
		Instances[Name] = Inst

		if Name == "REMOTE_FUNCTION" then
			(Inst :: RemoteFunction).OnServerInvoke = OnRemoteFunctionPacket
			continue
		end

		if Name == "BINDABLE_EVENT" then
			(Inst :: BindableEvent).Event:Connect(function(Args: { any })
				OnRemoteEventPacket(nil, Args, Name)
			end)

			continue
		end

		(Inst :: RemoteEvent --[[ | UnreliableRemoteEvent ]]).OnServerEvent:Connect(function(Player: Player, Args: { any })
			if not CheckPlayerRateLimit(Player, InstName :: "RemoteEvent" | "RemoteFunction" | "UnreliableRemoteEvent") then
				if DEBUG.RateLimitExceeded then
					warn(`[Dysconnect (DEBUG)] Player "{Player.Name}" with ID "{Player.UserId}" is suspected to be exhausting the remote calls rate limit! Cancelling current remote...`)
				end

				return
			end

			OnRemoteEventPacket(Player, Args, Name :: NetworkEventType)
		end)
	end

	Players.PlayerRemoving:Connect(function(Player: Player)
		--cleanup
		PlayerExhaustionLogs[Player.UserId] = nil
	end)

	print("[Dysconnect.Init()] Initialized networking on server successfully!")
end

const function ClientInit()
	ServerTimeStamp = script:GetAttribute("ServerTimeStamp") :: number?
	const EventFolder = script:FindFirstChild("Types") or script:WaitForChild("Types")

	for Name, _ in NAMING_EQUIVALENTS do
		Instances[Name] = EventFolder:FindFirstChild(Name) or EventFolder:WaitForChild(Name)

		if Name == "REMOTE_FUNCTION" then
			(Instances[Name] :: RemoteFunction).OnClientInvoke = function(Args: { any }): any
				return OnRemoteFunctionPacket(nil, Args)
			end

			continue
		end

		if Name == "BINDABLE_EVENT" then
			(Instances[Name] :: BindableEvent).Event:Connect(function(Args: { any })
				OnRemoteEventPacket(nil, Args, Name)
			end)

			continue
		end

		(Instances[Name] :: RemoteEvent --[[ | UnreliableRemoteEvent ]]).OnClientEvent:Connect(function(Args: { any })
			OnRemoteEventPacket(nil, Args, Name :: NetworkEventType)
		end)
	end

	print("[Dysconnect.Init()] Initialized networking on client successfully!")
end

--[=[
	@interface InitConfig
	@within Dysconnect
	
	Configurations to apply to the network service when initializing.
	
	.DebugConfig DEBUG -- Read [DEBUG].
	.ExhaustionDetectionConfig EXHAUSTION_DETECTION -- Read [EXHAUSTION_DETECTION].
	.Batching BATCHING -- Read [BATCHING].
]=]
type InitConfig = {
	DebugConfig: typeof(DEBUG)?,
	ExhaustionDetectionConfig: typeof(EXHAUSTION_DETECTION)?,
	Batching: typeof(BATCHING)?,
}
--[=[
	@within Dysconnect
	
	Initializes the networking system in the current environment.
	
	@param config InitConfig -- Read [InitConfig].
]=]
function Dysconnect.Init(config: InitConfig?)
	for Name, _ in NAMING_EQUIVALENTS do
		Connections[Name :: EventType] = {}
	end

	if config then
		if config.DebugConfig then
			DEBUG = table.freeze(WriteMissingTableValues(config.DebugConfig, DEBUG))
		end
		if config.ExhaustionDetectionConfig then
			EXHAUSTION_DETECTION = table.freeze(WriteMissingTableValues(config.ExhaustionDetectionConfig, EXHAUSTION_DETECTION))
		end
		if config.Batching then
			BATCHING = table.freeze(WriteMissingTableValues(config.Batching, BATCHING))
		end
	end

	if IS_SERVER then
		ServerInit()
	else
		ClientInit()
	end

	RunService.PostSimulation:Connect(FireQueuedCalls)

	ServiceLive = true
end

--[=[
	@within Dysconnect
	
	Adds a connection to a specific event / function instance.
	
	@param name string -- The name of the instance.
	@param Type EventType -- The type of the instance.
	@param Callback Callback -- The code that will run when the connection is fired.
	@param Predicate Predicate
	
	@return Connection -- The set connection for further usage and cleanup.
]=]
function Dysconnect.SetConnection(name: string, Type: EventType, Callback: Callback, Predicate: Predicate?): Connection
	if #name > 127 then
		warn(`[Dysconnect.SetConnection()] Can't assign connection with name "{name}" because it's too long! Try to shorten it a bit.`)
		return {
			Connected = false,
		} :: Connection
	end

	Dysconnect.WaitForInit()

	if Connections[Type][name] == nil and Type ~= "REMOTE_FUNCTION" then
		Connections[Type][name] = {}
	end
	if Type == "REMOTE_FUNCTION" then
		Connections[Type][name] = {
			Callback = Callback :: Callback,
			Predicate = Predicate,
		}
	else
		Connections[Type][name][Callback :: Callback] = {
			Predicate = Predicate,
		}
	end

	return setmetatable({
		Connected = true,
		Type = Type,
		Name = name,
		Callback = Callback,
	}, Connection) :: Connection
end

const function AddToQueue(player: (Player | { Player } | "All")?, name: string, Type: RemoteType, Args: Args)
	if DEBUG.SentPackets then
		print(`[Dysconnect (DEBUG)] Added event of type "{Type}" with name {name} to batch queue.\n{debug.traceback()}`)
	end

	if typeof(player) == "table" then
		for _, Target in player do
			table.insert(BatchQueue, {
				Target = Target,
				EventName = name,
				EventType = Type,
				Args = Args,
			})
		end

		return
	end

	table.insert(BatchQueue, {
		Target = player,
		EventName = name,
		EventType = Type,
		Args = Args,
	})
end

--[=[
	@within Dysconnect
	@server
	
	Fires a specific client's event / function connections.
	
	@param target Player -- The target client whose connections will be fired.
	@param name string -- The name of the desired event / function.
	@param Type InvokableType -- The type of instance to fire the connections of.
	@param ... any -- Any arguments to pass to the event.
	
	@return any | nil -- If a [RemoteFunction] is invoked using this, its returned values will be returned here.
]=]
function Dysconnect.FireClientConnection(target: Player | { Player }, name: string, Type: InvokableType, ...): any?
	if not target then
		warn(`[Dysconnect.FireClientConnection()] No target(s) for the event was/were provided!`, debug.traceback())
		return
	end

	if not name then
		warn(`[Dysconnect.FireClientConnection()] No name was provided for the event!`, debug.traceback())
		return
	end

	if #name > 127 then
		warn(`[Dysconnect.FireClientConnection()] Can't fire connection with name "{name}" because it's too long! Try to shorten it a bit.`)
		return
	end

	Dysconnect.WaitForInit()

	if not IS_SERVER then
		warn("[Dysconnect.FireClientConnection()] This function shouldn't be called from the client. Make sure that it isn't!", debug.traceback())
		return
	end

	const event = Instances[Type] :: RemoteFunction
	if not event then
		warn(`[Dysconnect.FireClientConnection()] Event {name} couldn't be fired because it doesn't exist! Are you sure you're spelling the type correctly? ({Type})`, debug.traceback())
		return
	end

	const Arguments = table.pack(...) --using table.pack() to add `Arguments.n`

	const ShouldBatch, CleanArgs = ExtractFireOptions(Arguments)
	if ShouldBatch then
		AddToQueue(target, name, Type :: RemoteType, CleanArgs :: Args)
		return
	end

	const CompressedArguments = PackArgumentsForNetwork(name, Arguments)

	if typeof(target) == "table" then
		const Results = {}
		for _, player: Player in target do
			Results[player.UserId] = table.pack(Fire(player, event, name, Type, CompressedArguments))
		end
		return Results
	end

	return Fire(target, event, name, Type, CompressedArguments)
end

--[=[
	@within Dysconnect
	@server
	
	Fires an event's connections to every single connected client. If the type of the object is a [RemoteFunction], it won't do anything.
	
	@param name string -- The name of the desired event.
	@param Type RemoteType -- The type of the event (Reliable / Unreliable).
	@param ... any -- Any arguments to pass to the event.
]=]
function Dysconnect.FireAllClientConnection(name: string, Type: RemoteType, ...)
	if not name then
		warn(`[Dysconnect.FireAllClientConnection()] No name was provided for the event!`, debug.traceback())
		return
	end

	if #name > 127 then
		warn(`[Dysconnect.FireAllClientConnection()] Can't fire connection with name "{name}" because it's too long! Try to shorten it a bit.`, debug.traceback())
		return
	end

	Dysconnect.WaitForInit()

	if not IS_SERVER then
		warn("[Dysconnect.FireAllClientConnection()] This function shouldn't be called from the client. Make sure that it isn't!", debug.traceback())
		return
	end

	if Type == "REMOTE_FUNCTION" or Type == "BINDABLE_EVENT" then
		warn(`[Dysconnect.FireAllClientConnection()] Event of type {Type} cannot be fired to every client at once!`, debug.traceback())
		return
	end

	const instance = Instances[Type] :: RemoteEvent --[[ | UnreliableRemoteEvent ]]
	if not instance then
		warn(`[Dysconnect.FireAllClientConnection()] Event {name} couldn't be fired because it doesn't exist! Are you sure you're connecting it to anything?`, debug.traceback())
		return
	end

	const Arguments = table.pack(...)

	const ShouldBatch, CleanArgs = ExtractFireOptions(Arguments)
	if ShouldBatch then
		AddToQueue("All", name, Type, CleanArgs :: Args)
		return
	end

	instance:FireAllClients(PackArgumentsForNetwork(name, Arguments))

	if DEBUG.SentPackets then
		print(`[Dysconnect (DEBUG)] Fired event of type "{Type}" with name "{name}".\n{debug.traceback()}`)
	end
end

--[=[
	@within Dysconnect
	@client
	
	Fires a connection on the server.
	
	@param name string -- The name of the desired event / function.
	@param Type InvokableType -- The type of instance to fire the connections of.
	@param ... any -- Any arguments to pass to the event.
	
	@return any | nil -- If a [RemoteFunction] is invoked using this, its returned values will be returned here.
]=]
function Dysconnect.FireServerConnection(name: string, Type: InvokableType, ...): any | nil
	if not name then
		warn(`[Dysconnect.FireServerConnection()] No name was provided for the event!`, debug.traceback())
		return
	end

	if #name > 127 then
		warn(`[Dysconnect.FireServerConnection()] Can't fire connection with name "{name}" because it's too long! Try to shorten it a bit.`)
		return
	end

	Dysconnect.WaitForInit()

	if IS_SERVER then
		warn("[Dysconnect.FireServerConnection()] This function shouldn't be called from the server. Make sure that it isn't!", debug.traceback())
		return
	end

	const instance = Instances[Type]
	if not instance then
		warn(`[Dysconnect.FireServerConnection()] Event {name} couldn't be fired because it doesn't exist! Are you sure you're spelling the type correctly? ({Type})`, debug.traceback())
		return
	end

	const Arguments = table.pack(...)

	if Type == "REMOTE_FUNCTION" then
		if DEBUG.SentPackets then
			print(`[Dysconnect (DEBUG)] Fired event of type "REMOTE_FUNCTION" with name "{name}".\n{debug.traceback()}`)
		end

		const Results = (instance :: RemoteFunction):InvokeServer(PackArgumentsForNetwork(name, Arguments))

		if DEBUG.ReceivedPackets then
			const BufferLength = Results[1] and typeof(Results[1]) == "buffer" and buffer.len(Results[1]) or 0
			print(`[Dysconnect (DEBUG)] Received back results from a "REMOTE_FUNCTION" with name "{name}" and a size of {BufferLength} bytes.`)
		end

		const _, DecompressedResults, ArgCount = UnpackArgumentsFromNetwork(Results)

		return UnpackArgTable(DecompressedResults, ArgCount)
	end

	const ShouldBatch, CleanArgs = ExtractFireOptions(Arguments)
	if ShouldBatch then
		AddToQueue(nil, name, Type, CleanArgs :: Args)
		return
	end

	(instance :: RemoteEvent --[[ | UnreliableRemoteEvent ]]):FireServer(PackArgumentsForNetwork(name, Arguments))

	return
end

--[=[
	@within Dysconnect
	
	Fires a BindableEvent's connections.
	
	@param name string -- The name of the desired BindableEvent.
	@param ... any -- Any arguments to pass to the event.
]=]
function Dysconnect.FireConnection(name: string, ...)
	if not name then
		warn(`[Dysconnect.FireConnection()] No name was provided for the event!`, debug.traceback())
		return
	end

	if #name > 127 then
		warn(`[Dysconnect.FireConnection()] Can't fire connection with name "{name}" because it's too long! Try to shorten it a bit.`)
		return
	end

	Dysconnect.WaitForInit()

	const Bindable = Instances["BINDABLE_EVENT"] :: BindableEvent
	if not Bindable then
		warn(
			`[Dysconnect.FireServerConnection()] Event {name} couldn't be fired because the main BindableEvent instance is missing! Are you sure the module is initializing properly?`,
			debug.traceback()
		)
		return
	end

	const Arguments = table.pack(...)
	const CompressedArguments = PackArgumentsForNetwork(name, Arguments)

	if DEBUG.SentPackets then
		print(`[Dysconnect (DEBUG)] Fired event of type "BINDABLE_EVENT" with name "{name}".\n{debug.traceback()}`)
	end

	Bindable:Fire(CompressedArguments)
end

--[=[
	@within Dysconnect
	
	Yields until the networking service is live for usage.
]=]
function Dysconnect.WaitForInit()
	while not ServiceLive do
		task.wait()
	end
end

--[=[
	@within Dysconnect
	
	Checks if this service is available.
	
	@return boolean -- If the network service is available in the current environment.
]=]
function Dysconnect.IsLive()
	return ServiceLive
end

table.freeze(Connection)
return table.freeze(Dysconnect)
