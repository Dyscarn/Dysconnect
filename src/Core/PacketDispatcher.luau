--!strict
--!optimize 2

const RunService = game:GetService("RunService")

const Types = require("../Types")
const Config = require("../Config")
const PacketSerializer = require("./PacketSerializer")
const ExhaustionDetector = require("../Net/ExhaustionDetector")
const ConnectionRegistry = require("../Net/ConnectionRegistry")

const IS_SERVER = RunService:IsServer()

const function Fire(player: Player, event: RemoteEvent | UnreliableRemoteEvent | RemoteFunction, name: string, Type: Types.InvokableType, ...): ...any
	if Config.Debug.SentPackets then
		print(`[Dysconnect (DEBUG)] Fired event of type "{Type}" with name "{name}".\n{debug.traceback()}`)
	end

	if Type == "REMOTE_FUNCTION" then
		const Results = (event :: RemoteFunction):InvokeClient(player, ...)

		if Config.Debug.ReceivedPackets then
			const BufferLength = Results[1] and typeof(Results[1]) == "buffer" and buffer.len(Results[1]) or 0
			print(`[Dysconnect (DEBUG)] Received back results from a "REMOTE_FUNCTION" with name "{name}" and a size of {BufferLength} bytes.`)
		end

		const _, DecompressedResults, ArgCount = PacketSerializer.UnpackArgumentsFromNetwork(Results)
		return PacketSerializer.UnpackArgTable(DecompressedResults, ArgCount)
	else
		(event :: RemoteEvent --[[ | UnreliableRemoteEvent ]]):FireClient(player, ...)
	end
	return
end

const function ReceiveCall(Player: Player?, name: string, Type: Types.NetworkEventType, ...)
	const CallbackList = ConnectionRegistry.GetConnectionsByName(Type, name)
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
			task.spawn(callback :: (...any) -> ...any, Player :: Player, ...)
		else
			task.spawn(callback :: (...any) -> ...any, ...)
		end
	end
end

const function OnRemoteEventPacket(Player: Player?, Args: { any }, Type: Types.NetworkEventType)
	--safety first gng
	if Type ~= "BINDABLE_EVENT" and IS_SERVER and not Player then
		return
	end

	const Name, DecodedArgs, _ArgCount, InstanceCount = PacketSerializer.UnpackArgumentsFromNetwork(Args)

	if Name == "__Batch" then
		if Config.Debug.ReceivedPackets and (Type ~= "UREMOTE_EVENT" or not Config.Debug.ExcludeUnreliable) then
			const BufferLength = Args[1] and typeof(Args[1]) == "buffer" and buffer.len(Args[1]) or #Name
			print(
				`[Dysconnect (DEBUG)] Received event batch of type "{Type}" and a size of {BufferLength} bytes{InstanceCount > 0 and `, with a total of {InstanceCount} instance{InstanceCount > 1 and "s" or ""}.` or "."}`
			)
		end

		const Entries = PacketSerializer.UnpackBatchEnvelope(DecodedArgs[1], DecodedArgs[2] or {})

		for _, Entry in Entries do
			if Config.Debug.ReceivedPackets and (Type ~= "UREMOTE_EVENT" or not Config.Debug.ExcludeUnreliable) and (Entry.EventName:sub(0, 2) ~= "__" or not Config.Debug.ExcludeReserved) then
				const BufferLength = PacketSerializer.GetSizeOfBatchEvent(Entry.EventName, Entry.Args)
				const NameLength = #Entry.EventName
				const ArgsLength = math.max(0, BufferLength - NameLength)
				print(
					`[Dysconnect (DEBUG)] Received batched event of type "{Type}" with name "{Entry.EventName}" and a size of {BufferLength} bytes ({NameLength} bytes for the name, {ArgsLength} bytes for the arguments{InstanceCount > 0 and `, with a total of {InstanceCount} instance{InstanceCount > 1 and "s" or ""}.` or ")."}`
				)
			end

			ReceiveCall(Player, Entry.EventName, Type, PacketSerializer.UnpackArgTable(Entry.Args))
		end

		return
	end

	if Config.Debug.ReceivedPackets and (Type ~= "UREMOTE_EVENT" or not Config.Debug.ExcludeUnreliable) and (Name:sub(0, 2) ~= "__" or not Config.Debug.ExcludeReserved) then
		const BufferLength = Args[1] and typeof(Args[1]) == "buffer" and buffer.len(Args[1]) or #Name
		const NameLength = #Name
		const ArgsLength = math.max(0, BufferLength - NameLength)
		print(
			`[Dysconnect (DEBUG)] Received event of type "{Type}" with name "{Name}" and a size of {BufferLength} bytes ({NameLength} bytes for the name, {ArgsLength} bytes for the arguments{InstanceCount > 0 and `, with a total of {InstanceCount} instance{InstanceCount > 1 and "s" or ""}.` or ")."}`
		)
	end

	ReceiveCall(Player, Name, Type, PacketSerializer.UnpackArgTable(DecodedArgs))
end

const function OnRemoteFunctionPacket(Player: Player?, Args: { any }): any
	--safety first gng
	if IS_SERVER then
		if not Player then
			return
		end

		if not ExhaustionDetector.CheckPlayerRateLimit(Player, "RemoteFunction") then
			if Config.Debug.RateLimitExceeded then
				warn(`[Dysconnect (DEBUG)] Player "{Player.Name}" with ID "{Player.UserId}" is suspected to be exhausting the remote calls rate limit! Cancelling current remote...`)
			end

			return
		end
	end

	const Name, DecodedArgs, _ArgCount, InstanceCount = PacketSerializer.UnpackArgumentsFromNetwork(Args)

	if Config.Debug.ReceivedPackets then
		const BufferLength = Args[1] and typeof(Args[1]) == "buffer" and buffer.len(Args[1]) or 0
		const NameLength = #Name
		const ArgsLength = math.max(0, BufferLength - NameLength)
		print(
			`[Dysconnect (DEBUG)] Received event of type "REMOTE_FUNCTION" with name "{Name}" and a size of {BufferLength} bytes ({NameLength} bytes for the name, {ArgsLength} bytes for the arguments{InstanceCount > 0 and `, with a total of {InstanceCount} instance{InstanceCount > 1 and "s" or ""}.` or ")."}`
		)
	end

	const Meta = ConnectionRegistry.GetConnectionsByName("REMOTE_FUNCTION" :: Types.NetworkEventType, Name)
	if not Meta then
		return
	end

	if Meta.Predicate then
		const Valid = if IS_SERVER
			then (Meta.Predicate :: (Player: Player, ...any) -> boolean)(Player :: Player, PacketSerializer.UnpackArgTable(DecodedArgs))
			else (Meta.Predicate :: (...any) -> boolean)(PacketSerializer.UnpackArgTable(DecodedArgs) :: any)

		if not Valid then
			return
		end
	end

	const Results = if IS_SERVER
		then table.pack((Meta.Callback :: (Player: Player, ...any) -> ())(Player :: Player, PacketSerializer.UnpackArgTable(DecodedArgs)))
		else table.pack((Meta.Callback :: (...any) -> ())(PacketSerializer.UnpackArgTable(DecodedArgs) :: any))

	if Results == nil then
		return
	end

	const CompressedResults = PacketSerializer.PackArgumentsForNetwork("_RFunc", Results) --using a dummy name, ignore

	return CompressedResults
end

return table.freeze({
	ReceiveCall = ReceiveCall,
	Fire = Fire,
	OnRemoteEventPacket = OnRemoteEventPacket,
	OnRemoteFunctionPacket = OnRemoteFunctionPacket,
})
