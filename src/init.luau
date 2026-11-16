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
--!optimize 2

--[[
	The type checking in this module is actually pretty damn messy.
	It's one of the first times I use strict typing in a serious way,
	and complying with everything it says is hard. :(
	
	I'll look into improving typing here in the future.
	
	-dys
]]

const RunService = game:GetService("RunService")

const Types = require("@self/Types")
const Config = require("@self/Config")
const IdAllocator = require("@self/Net/IdAllocator")
const Transmission = require("@self/Net/Transmission")
const BatchDispatcher = require("@self/Core/BatchDispatcher")
const PacketDispatcher = require("@self/Core/PacketDispatcher")
const ConnectionRegistry = require("@self/Net/ConnectionRegistry")
const ExhaustionDetector = require("@self/Net/ExhaustionDetector")
const IdentifierRegistry = require("@self/Core/IdentifierRegistry")

const IS_SERVER = RunService:IsServer()

const RESERVED_IDS = table.freeze({
	__IdAssignment = 0,
	__Batch = 1,
	__RFunc = 2,
}) :: { [string]: number }
for Name, ID in RESERVED_IDS do
	IdentifierRegistry.GenerateIdForName(Name, ID)
end

--[=[
	@class Dysconnect
	
	Class used to connect the server and the clients more efficiently by encapsulating everything in a single place.
]=]

const NAMING_EQUIVALENTS = table.freeze({
	REMOTE_EVENT = "RemoteEvent",
	REMOTE_FUNCTION = "RemoteFunction",
	UREMOTE_EVENT = "UnreliableRemoteEvent",
	BINDABLE_EVENT = "BindableEvent",
}) :: typeof(table.freeze({} :: { [Types.EventType]: string }))

const function WriteMissingTableValues<T, S>(Target: T & {}, Values: S & {}): T & S & {}
	for Key, Value in Values :: { [any]: any } do
		if Target[Key] ~= nil then
			continue
		end

		Target[Key] = Value
	end

	return Target
end

const function Destroy()
	script:ClearAllChildren()
	ConnectionRegistry.Destroy()
end

@native
const function ServerIdAssignment(Player: Player)
	const All = {} :: { number | string }
	local ByteSize = 0
	local Count = 0
	for Name, ID in IdAllocator.GetObjectIds() do
		table.insert(All, Name)
		table.insert(All, ID)
		Count += 1
		ByteSize += 5 + #Name -- 2 byte (ID amount) + 1 byte (name length) + Name length + 2 bytes (ID length)
	end

	const Packet = buffer.create(ByteSize)
	buffer.writeu16(Packet, 0, Count)
	local Offset = 2
	for Index, Item in All do
		if Index % 2 == 1 then --is a name
			buffer.writeu8(Packet, Offset, #(Item :: string))
			Offset += 1
			buffer.writestring(Packet, Offset, Item :: string)
			Offset += #(Item :: string)
			continue
		end

		buffer.writeu16(Packet, Offset, Item :: number)
		Offset += 2
	end

	Transmission.FireClientConnection(Player, "__IdAssignment", "REMOTE_EVENT" :: Types.InvokableType, Packet, Transmission.FireOptions({ Batch = false }))
end

@native
const function ClientIdAssignment(Packet: buffer)
	const Count = buffer.readu16(Packet, 0)
	local Offset = 2
	for _ = 1, Count do
		const NameLength = buffer.readu8(Packet, Offset)
		Offset += 1
		const Name = buffer.readstring(Packet, Offset, NameLength)
		Offset += NameLength
		const ID = buffer.readu16(Packet, Offset)
		Offset += 2

		if RESERVED_IDS[Name] == ID or IdAllocator.GetIDByObject(Name) == ID then
			continue
		end
		IdentifierRegistry.GenerateIdForName(Name, ID)
	end

	script:SetAttribute("ClientReady", true)
end

const function ServerInit(): { [Types.EventType]: Instance }
	game:BindToClose(Destroy)

	local InstanceFolder = script:FindFirstChild("Instances") :: Folder
	if not InstanceFolder then
		InstanceFolder = Instance.new("Folder")
		InstanceFolder.Name = "Instances"
		InstanceFolder.Parent = script
	end

	const Instances = {} :: { [Types.EventType]: Instance }
	for Name, InstName in NAMING_EQUIVALENTS do
		local Inst = InstanceFolder:FindFirstChild(InstName) :: Instance
		if not Inst then
			Inst = Instance.new(InstName)
			Inst.Name = Name
			Inst.Parent = InstanceFolder
		end
		Instances[Name] = Inst

		if Name == "REMOTE_FUNCTION" then
			(Inst :: RemoteFunction).OnServerInvoke = PacketDispatcher.OnRemoteFunctionPacket
			continue
		end

		if Name == "BINDABLE_EVENT" then
			(Inst :: BindableEvent).Event:Connect(function(Args: { any })
				PacketDispatcher.OnRemoteEventPacket(nil, Args, Name)
			end)

			continue
		end

		(Inst :: RemoteEvent --[[ | UnreliableRemoteEvent ]]).OnServerEvent:Connect(function(Player: Player, Args: { any })
			if not ExhaustionDetector.CheckPlayerRateLimit(Player, InstName :: "RemoteEvent" | "RemoteFunction" | "UnreliableRemoteEvent") then
				if Config.Debug.RateLimitExceeded then
					warn(`[Dysconnect (DEBUG)] Player "{Player.Name}" with ID "{Player.UserId}" is suspected to be exhausting the remote calls rate limit! Cancelling current remote...`)
				end

				return
			end

			PacketDispatcher.OnRemoteEventPacket(Player, Args, Name :: Types.NetworkEventType)
		end)
	end

	ExhaustionDetector.Setup()

	script:SetAttribute("ServerReady", true)

	print("[Dysconnect.Init()] Initialized networking on server successfully!")

	return Instances
end

const function ClientInit(): { [Types.EventType]: Instance }
	const InstanceFolder = script:FindFirstChild("Instances") or script:WaitForChild("Instances")

	const Instances = {} :: { [Types.EventType]: Instance }
	for Name, _ in NAMING_EQUIVALENTS do
		Instances[Name] = InstanceFolder:FindFirstChild(Name) or InstanceFolder:WaitForChild(Name)

		if Name == "REMOTE_FUNCTION" then
			(Instances[Name] :: RemoteFunction).OnClientInvoke = function(Args: { any }): any
				return PacketDispatcher.OnRemoteFunctionPacket(nil, Args)
			end

			continue
		end

		if Name == "BINDABLE_EVENT" then
			(Instances[Name] :: BindableEvent).Event:Connect(function(Args: { any })
				PacketDispatcher.OnRemoteEventPacket(nil, Args, Name)
			end)

			continue
		end

		(Instances[Name] :: RemoteEvent --[[ | UnreliableRemoteEvent ]]).OnClientEvent:Connect(function(Args: { any })
			PacketDispatcher.OnRemoteEventPacket(nil, Args, Name :: Types.NetworkEventType)
		end)
	end

	print("[Dysconnect.Init()] Initialized networking on client successfully!")

	return Instances
end

--[=[
	@within Dysconnect
	
	Initializes the networking system in the current environment.
	
	@param config InitConfig -- Read [InitConfig].
]=]
const function Init(config: Config.InitConfig?)
	Transmission.AddToQueue = BatchDispatcher.AddToQueue
	ConnectionRegistry.Setup(NAMING_EQUIVALENTS)

	if config then
		if config.DebugConfig then
			Config.Debug = table.freeze(WriteMissingTableValues(config.DebugConfig, Config.Debug))
		end
		if config.ExhaustionDetectionConfig then
			Config.ExhaustionDetection = table.freeze(WriteMissingTableValues(config.ExhaustionDetectionConfig, Config.ExhaustionDetection))
		end
		if config.Batching then
			Config.Batching = table.freeze(WriteMissingTableValues(config.Batching, Config.Batching))
		end
	end

	const Instances = if IS_SERVER then ServerInit() else ClientInit()

	RunService.PostSimulation:Connect(BatchDispatcher.FireQueuedCalls)

	Transmission.GoLive(Instances)

	Transmission.SetConnection("__IdAssignment", "REMOTE_EVENT", if IS_SERVER then ServerIdAssignment else ClientIdAssignment)

	if not IS_SERVER then
		if not script:GetAttribute("ServerReady") then
			script:GetAttributeChangedSignal("ServerReady"):Wait()
		end

		Transmission.FireServerConnection("__IdAssignment", "REMOTE_EVENT", Transmission.FireOptions({ Batch = false }))
	end
end

return table.freeze({
	Init = Init,
	FireClientConnection = Transmission.FireClientConnection,
	FireAllClientConnection = Transmission.FireAllClientConnection,
	FireServerConnection = Transmission.FireServerConnection,
	FireConnection = Transmission.FireConnection,
	SetConnection = Transmission.SetConnection,
	FireOptions = Transmission.FireOptions,
	IsLive = Transmission.IsLive,
	WaitForInit = Transmission.WaitForInit,
})
