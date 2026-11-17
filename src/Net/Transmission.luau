--!strict
--!optimize 2

const RunService = game:GetService("RunService")

const PacketDispatcher = require("../Core/PacketDispatcher")
const Types = require("../Types")
const Config = require("../Config")
const IdentifierAllocator = require("./IdentifierAllocator")
const ConnectionRegistry = require("./ConnectionRegistry")
const PacketSerializer = require("../Core/PacketSerializer")

const IS_SERVER = RunService:IsServer()

const Transmission = { AddToQueue = nil :: ((player: (Player | { Player } | "All")?, name: string, Type: Types.RemoteType, Args: Types.Args) -> ())? }

local ServiceLive = false

function Transmission.GoLive(_Instances: { [Types.EventType]: Instance })
	Transmission.Instances = _Instances
	table.freeze(Transmission)
	ServiceLive = true
end

--[=[
	@within Dysconnect
	
	Checks if this service is available.
	
	@return boolean -- If the network service is available in the current environment.
]=]
function Transmission.IsLive()
	return ServiceLive
end
--[=[
	@within Dysconnect
	
	Yields until the networking service is live for usage.
]=]
function Transmission.WaitForInit()
	while not ServiceLive do
		task.wait()
	end
end

@native
const function CreateMissingIdBuffer(name: string, Id: number): buffer
	const ByteSize = 5 + #name -- 2 bytes (ID count) + 1 byte (name length) + Name length + 2 bytes (ID)
	const Packet = buffer.create(ByteSize)
	buffer.writeu16(Packet, 0, 1)
	buffer.writeu8(Packet, 2, #name)
	buffer.writestring(Packet, 3, name)
	buffer.writeu16(Packet, 3 + #name, Id)
	return Packet
end

const function GenerateIdForName(Name: string, Override: number?): number
	if IS_SERVER then
		return IdentifierAllocator.Register(Name, Override)
	end

	return Override or -1
end

const function CreateMissingID(name: string)
	if IdentifierAllocator.GetIDByObject(name) ~= nil then
		return
	end

	const NewId = GenerateIdForName(name)
	Transmission.FireAllClientConnection("__IdAssignment", "REMOTE_EVENT", CreateMissingIdBuffer(name, NewId), Transmission.FireOptions({ Batch = false }))
end

--[=[
	@within Dysconnect
	@server
	
	Fires an event's connections to every single connected client. If the type of the object is a [RemoteFunction], it won't do anything.
	
	@param name string -- The name of the desired event.
	@param Type RemoteType -- The type of the event (Reliable / Unreliable).
	@param ... any -- Any arguments to pass to the event.
]=]
function Transmission.FireAllClientConnection(name: string, Type: Types.RemoteType, ...)
	if not name then
		warn(`[Dysconnect.FireAllClientConnection()] No name was provided for the event!`, debug.traceback())
		return
	end

	if #name > 127 then
		warn(`[Dysconnect.FireAllClientConnection()] Can't fire connection with name "{name}" because it's too long! Try to shorten it a bit.`, debug.traceback())
		return
	end

	Transmission.WaitForInit()

	if not IS_SERVER then
		warn("[Dysconnect.FireAllClientConnection()] This function shouldn't be called from the client. Make sure that it isn't!", debug.traceback())
		return
	end

	if Type == "REMOTE_FUNCTION" or Type == "BINDABLE_EVENT" then
		warn(`[Dysconnect.FireAllClientConnection()] Event of type {Type} cannot be fired to every client at once!`, debug.traceback())
		return
	end

	const instance = Transmission.Instances[Type] :: RemoteEvent --[[ | UnreliableRemoteEvent ]]
	if not instance then
		warn(`[Dysconnect.FireAllClientConnection()] Event {name} couldn't be fired because it doesn't exist! Are you sure you're connecting it to anything?`, debug.traceback())
		return
	end

	CreateMissingID(name)

	const Arguments = table.pack(...)

	const ShouldBatch, CleanArgs = PacketSerializer.ExtractFireOptions(Arguments)
	if ShouldBatch and Transmission.AddToQueue then
		Transmission.AddToQueue("All", name, Type, CleanArgs :: Types.Args)
		return
	end

	instance:FireAllClients(PacketSerializer.PackArgumentsForNetwork(name, CleanArgs :: Types.Args))

	if Config.Debug.SentPackets then
		print(`[Dysconnect (DEBUG)] Fired event of type "{Type}" with name "{name}".\n{debug.traceback()}`)
	end
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
function Transmission.SetConnection(name: string, Type: Types.EventType, Callback: Types.Callback, Predicate: Types.Predicate?): Types.Connection
	if #name > 127 then
		warn(`[Dysconnect.SetConnection()] Can't assign connection with name "{name}" because it's too long! Try to shorten it a bit.`)
		return {
			Connected = false,
		} :: Types.Connection
	end

	-- Dysconnect.WaitForInit()
	--only wait for the connection table to appear instead
	ConnectionRegistry.WaitForConnectionType(Type)

	if IS_SERVER then
		CreateMissingID(name)
	end

	ConnectionRegistry.Create(Type, name, Callback, Predicate)

	return setmetatable({
		Connected = true,
		Type = Type,
		Name = name,
		Callback = Callback,
	}, ConnectionRegistry.MetaConnection) :: Types.Connection
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
function Transmission.FireClientConnection(target: Player | { Player }, name: string, Type: Types.InvokableType, ...): any?
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

	Transmission.WaitForInit()

	if not IS_SERVER then
		warn("[Dysconnect.FireClientConnection()] This function shouldn't be called from the client. Make sure that it isn't!", debug.traceback())
		return
	end

	const event = Transmission.Instances[Type] :: RemoteFunction
	if not event then
		warn(`[Dysconnect.FireClientConnection()] Event {name} couldn't be fired because it doesn't exist! Are you sure you're spelling the type correctly? ({Type})`, debug.traceback())
		return
	end

	CreateMissingID(name)

	const Arguments = table.pack(...) --using table.pack() to add `Arguments.n`

	const ShouldBatch, CleanArgs = PacketSerializer.ExtractFireOptions(Arguments)
	if ShouldBatch and Transmission.AddToQueue then
		Transmission.AddToQueue(target, name, Type :: Types.RemoteType, CleanArgs :: Types.Args)
		return
	end

	const CompressedArguments = PacketSerializer.PackArgumentsForNetwork(name, CleanArgs :: Types.Args)

	if typeof(target) == "table" then
		const Results = {}
		for _, player: Player in target do
			Results[player.UserId] = table.pack(PacketDispatcher.Fire(player, event, name, Type, CompressedArguments))
		end
		return Results
	end

	return PacketDispatcher.Fire(target, event, name, Type, CompressedArguments)
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
function Transmission.FireServerConnection(name: string, Type: Types.InvokableType, ...): any | nil
	if not name then
		warn(`[Dysconnect.FireServerConnection()] No name was provided for the event!`, debug.traceback())
		return
	end

	if #name > 127 then
		warn(`[Dysconnect.FireServerConnection()] Can't fire connection with name "{name}" because it's too long! Try to shorten it a bit.`)
		return
	end

	Transmission.WaitForInit()

	if IS_SERVER then
		warn("[Dysconnect.FireServerConnection()] This function shouldn't be called from the server. Make sure that it isn't!", debug.traceback())
		return
	end

	const instance = Transmission.Instances[Type]
	if not instance then
		warn(`[Dysconnect.FireServerConnection()] Event {name} couldn't be fired because it doesn't exist! Are you sure you're spelling the type correctly? ({Type})`, debug.traceback())
		return
	end

	const Arguments = table.pack(...)

	if Type == "REMOTE_FUNCTION" then
		if Config.Debug.SentPackets and (name:sub(0, 2) ~= "__" or not Config.Debug.ExcludeReserved) then
			print(`[Dysconnect (DEBUG)] Fired event of type "REMOTE_FUNCTION" with name "{name}".\n{debug.traceback()}`)
		end

		const Results = (instance :: RemoteFunction):InvokeServer(PacketSerializer.PackArgumentsForNetwork(name, Arguments))

		if Config.Debug.ReceivedPackets then
			const BufferLength = Results[1] and typeof(Results[1]) == "buffer" and buffer.len(Results[1]) or 0
			print(`[Dysconnect (DEBUG)] Received back results from a "REMOTE_FUNCTION" with name "{name}" and a size of {BufferLength} bytes.`)
		end

		const _, DecompressedResults, ArgCount = PacketSerializer.UnpackArgumentsFromNetwork(Results)

		return PacketSerializer.UnpackArgTable(DecompressedResults, ArgCount)
	end

	const ShouldBatch, CleanArgs = PacketSerializer.ExtractFireOptions(Arguments)
	if ShouldBatch and Transmission.AddToQueue then
		Transmission.AddToQueue(nil, name, Type, CleanArgs :: Types.Args)
		return
	end

	if Config.Debug.SentPackets and (name:sub(0, 2) ~= "__" or not Config.Debug.ExcludeReserved) then
		print(`[Dysconnect (DEBUG)] Fired event of type "{Type}" with name "{name}".\n{debug.traceback()}`)
	end

	(instance :: RemoteEvent --[[ | UnreliableRemoteEvent ]]):FireServer(PacketSerializer.PackArgumentsForNetwork(name, CleanArgs :: Types.Args))

	return
end

--[=[
	@within Dysconnect
	
	Fires a BindableEvent's connections.
	
	@param name string -- The name of the desired BindableEvent.
	@param ... any -- Any arguments to pass to the event.
]=]
function Transmission.FireConnection(name: string, ...)
	if not name then
		warn(`[Dysconnect.FireConnection()] No name was provided for the event!`, debug.traceback())
		return
	end

	if #name > 127 then
		warn(`[Dysconnect.FireConnection()] Can't fire connection with name "{name}" because it's too long! Try to shorten it a bit.`)
		return
	end

	Transmission.WaitForInit()

	const Bindable = Transmission.Instances["BINDABLE_EVENT"] :: BindableEvent
	if not Bindable then
		warn(
			`[Dysconnect.FireServerConnection()] Event {name} couldn't be fired because the main BindableEvent instance is missing! Are you sure the module is initializing properly?`,
			debug.traceback()
		)
		return
	end

	const CompressedArguments = PacketSerializer.PackArgumentsForNetwork(name, table.pack(...))

	if Config.Debug.SentPackets and (name:sub(0, 2) ~= "__" or not Config.Debug.ExcludeReserved) then
		print(`[Dysconnect (DEBUG)] Fired event of type "BINDABLE_EVENT" with name "{name}".\n{debug.traceback()}`)
	end

	Bindable:Fire(CompressedArguments)
end

--[=[
	@within Dysconnect
	
	Makes a [FireOptions] table for usage in a remote call
	This should be used instead of directly making a table as this adds a custom header to identify
	that these are [FireOptions].
	
	@param Options FireOptions -- The options to apply to it.
	@return FireOptions -- The [FireOptions] to use, with a custom header.
]=]
function Transmission.FireOptions(Options: Types.FireOptions): Types.BuiltFireOptions
	--type casting it here so i don't have to make a different table for it while keeping it strict
	(Options :: Types.BuiltFireOptions).__DysconnectFireOptions = true
	return table.freeze(Options) :: Types.BuiltFireOptions
end

return Transmission
