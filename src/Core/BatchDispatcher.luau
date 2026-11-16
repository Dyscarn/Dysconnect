--!strict
--!optimize 2

const RunService = game:GetService("RunService")

const Types = require("../Types")
const Config = require("../Config")
const Transmission = require("../Net/Transmission")
const PacketSerializer = require("./PacketSerializer")

const IS_SERVER = RunService:IsServer()

const BatchQueue = {} :: { Types.TargetedBatchPacket }

const function AddToQueue(player: (Player | { Player } | "All")?, name: string, Type: Types.RemoteType, Args: Types.Args)
	if Config.Debug.SentPackets then
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

const Entrypoint = script.Parent.Parent
const function FireQueuedCalls()
	if #BatchQueue == 0 then
		return
	end

	if not IS_SERVER and not Entrypoint:GetAttribute("ClientReady") then
		return
	end

	const SelectedCalls = {
		REMOTE_EVENT = {},
		UREMOTE_EVENT = {},
	} :: { [Types.RemoteType]: { [Player | "All" | "Server"]: { Types.BatchPacket } } }
	local AccumulatedSizes = {
		REMOTE_EVENT = {},
		UREMOTE_EVENT = {},
	} :: { [Types.RemoteType]: { [Player | "All" | "Server"]: number } }
	const IndexesToRemove = {} :: { number }
	for Index, Event in BatchQueue do
		const BufferLength = PacketSerializer.GetSizeOfBatchEvent(Event.EventName, Event.Args)
		const EventType = Event.EventType
		const EventTarget = Event.Target or "Server"

		const ExistingAccumulated = AccumulatedSizes[EventType][EventTarget]
		if ExistingAccumulated and ExistingAccumulated > Config.Batching.MaxBatchSize then
			continue
		end

		const Size = BufferLength / 1024
		--if the size of the call args is already bigger than the max limit, just send it immediately
		if Size >= Config.Batching.MaxBatchSize then
			--only remove it from queue if it's bigger than the cap or if it's sent
			table.insert(IndexesToRemove, Index)
			-- gotta add FireOptions here so it doesn't try to batch it again at all,
			-- which would make an infinite loop of doom and despair
			const Options = Transmission.FireOptions({ Batch = false })
			if Event.Target == "Server" then
				if not IS_SERVER then
					Transmission.FireServerConnection(Event.EventName, EventType, table.unpack(Event.Args), Options)
				end
			elseif IS_SERVER then
				if Event.Target == "All" then
					Transmission.FireAllClientConnection(Event.EventName, EventType, table.unpack(Event.Args), Options)
				else
					Transmission.FireClientConnection(EventTarget :: Player, Event.EventName, EventType, table.unpack(Event.Args), Options)
				end
			end
			continue
		end
		--if adding the event would exceed the cap, but the event isn't bigger than or as big as the cap, skip it
		if ExistingAccumulated and ExistingAccumulated + Size > Config.Batching.MaxBatchSize then
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
		local CallGroup: { Types.BatchPacket }
		if Calls[EventTarget] == nil then
			Calls[EventTarget] = {}
		end
		CallGroup = Calls[EventTarget]
		table.insert(CallGroup, Event :: Types.BatchPacket)
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
		const event = Transmission.Instances[Type] :: RemoteEvent --[[ | UnreliableRemoteEvent ]]
		if not event then
			continue
		end

		for Target, Events in CallGroup do
			const EnvelopeBuffer, InstanceList = PacketSerializer.PackBatchEnvelope(Events)
			-- Compressing it like this will add slight but negligible overhead
			-- because of an attempt to serialize InstanceList and failing,
			-- but it's not like i care enough to change it.
			-- -dys
			const Compressed = PacketSerializer.PackArgumentsForNetwork("__Batch", table.pack(EnvelopeBuffer, InstanceList))

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

return table.freeze({
	AddToQueue = AddToQueue,
	FireQueuedCalls = FireQueuedCalls,
})
