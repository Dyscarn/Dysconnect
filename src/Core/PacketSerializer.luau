--!strict
--!optimize 2
--!native

const Types = require("../Types")
const Config = require("../Config")
const BinaryCodec = require("../Net/BinaryCodec")
const IdentifierRegistry = require("./IdentifierRegistry")

const function GetSizeOfBatchEvent(Args: Types.Args): number
	local Size = 5 --4 + 1 for event id
	for i = 1, Args.n do
		const Arg = Args[i]
		-- + 1 for tag
		Size += 1 + BinaryCodec.GetPayloadSize(BinaryCodec.GetTagFromValue(Arg), Arg)
	end
	return Size
end

const function UnpackArgTable(ArgTable: { [any]: any }): ...any
	return table.unpack(ArgTable, 1, ArgTable.n)
end

const function PackArgumentsForNetwork(Name: string, Arguments: Types.Args): { any }
	const NameId = IdentifierRegistry.GetIDFromName(Name)
	if Arguments.n == 0 then
		return { NameId }
	end

	--calculate the total size of the buffer
	local TotalSize = 1 --1 for event name id
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
		const Tag = BinaryCodec.GetTagFromValue(Value)

		if Config.Debug.Strict and Tag == BinaryCodec.Enum.JSON then
			warn(`[Dysconnect (DEBUG)] Data type "{typeof(Value)}" isn't officially supported by Dysconnect to auto-optimize into a buffer! Falling back to JSON strings...`)
		end

		--get le size
		const PayloadSize = BinaryCodec.GetPayloadSize(Tag, Value)

		--add le size to total + 1 for the tag
		TotalSize += (1 + PayloadSize)

		table.insert(PreparedArgs, {
			Tag = Tag,
			Value = Value,
			Size = PayloadSize,
		})
	end

	TotalSize = 2
	if Arguments.n == 1 then
		TotalSize += (2 + PreparedArgs[1].Size)
	else
		TotalSize += 1
		for _, Item in PreparedArgs do
			TotalSize += (1 + Item.Size)
		end
	end

	--create the buffer
	const PacketBuffer = buffer.create(TotalSize)

	if Arguments.n == 1 then
		buffer.writeu16(PacketBuffer, 0, NameId)
		buffer.writeu8(PacketBuffer, 2, 1)
		buffer.writeu8(PacketBuffer, 3, PreparedArgs[1].Tag)
		BinaryCodec.GetWriter(PreparedArgs[1].Tag)(PacketBuffer, 4, PreparedArgs[1].Value, InstanceList)
	else
		buffer.writeu16(PacketBuffer, 0, NameId)
		buffer.writeu8(PacketBuffer, 2, Arguments.n)
		local Offset = 3

		for _, Item in PreparedArgs do
			--write le tag first
			buffer.writeu8(PacketBuffer, Offset, Item.Tag)
			--write it and increment the offset based on it
			Offset = BinaryCodec.GetWriter(Item.Tag)(PacketBuffer, Offset + 1, Item.Value, InstanceList)
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

	const ID = buffer.readu16(PacketBuffer, 0)
	const ArgCount = buffer.readu8(PacketBuffer, 2)
	local Name = IdentifierRegistry.GetNameFromID(ID)

	local Offset: number
	local Unpacked: Types.Args

	if ArgCount == 1 then
		Unpacked = table.create(1) :: Types.Args
		Unpacked.n = 1

		Offset = 3
		const Tag = buffer.readu8(PacketBuffer, Offset)
		const Value = BinaryCodec.GetReader(Tag)(PacketBuffer, Offset + 1, InstanceList)
		Unpacked[1] = Value
	else
		Unpacked = table.create(ArgCount) :: Types.Args
		Unpacked.n = ArgCount

		Offset = 3
		--loop until the whole buffer is read
		for i = 1, ArgCount do
			--le tag
			const Tag = buffer.readu8(PacketBuffer, Offset)
			Offset += 1

			--get correspondent value
			const Value, NewCursor = BinaryCodec.GetReader(Tag)(PacketBuffer, Offset, InstanceList)

			--put it in the param table
			Unpacked[i] = Value
			--increase pointer
			Offset = NewCursor
		end
	end

	--FINALLY return the thing for usage
	return Name, Unpacked, Unpacked.n, #InstanceList
end

const function PackBatchEnvelope(Entries: { Types.BatchPacket }): (buffer, { Instance })
	const EntryCount = #Entries
	local TotalSize = 4

	const InstanceList = {} :: { Instance }

	const Prepared = {} :: {
		{
			Name: string,
			Args: { { Tag: number, Value: any, Size: number } },
			Size: number,
			Offset: number,
		}
	}

	for _, Entry in Entries do
		-- TotalSize += 4 + #Entry.EventName
		TotalSize += 5 --4 + 1 for event id

		const EntryArgs = {} :: { { Tag: number, Value: any, Size: number } }
		local EntrySize = 0

		for i = 1, Entry.Args.n do
			const Value = Entry.Args[i]
			const Tag = BinaryCodec.GetTagFromValue(Value)

			const PayloadSize = BinaryCodec.GetPayloadSize(Tag, Value)
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

	for _, Payload in Prepared do
		Payload.Offset = Offset

		buffer.writeu16(Buffer, Offset, IdentifierRegistry.GetIDFromName(Payload.Name))
		Offset += 2

		buffer.writeu8(Buffer, Offset, #Payload.Args)
		Offset += 1

		buffer.writeu16(Buffer, Offset, Payload.Size)
		Offset += 2

		for _, Arg in Payload.Args do
			buffer.writeu8(Buffer, Offset, Arg.Tag)
			Offset += 1
			Offset = BinaryCodec.GetWriter(Arg.Tag)(Buffer, Offset, Arg.Value, InstanceList)
		end
	end

	return Buffer, InstanceList
end

const function UnpackBatchEnvelope(Buffer: buffer, InstanceList: { Instance }): { Types.ReceivedBatchPacket }
	local Offset = 0

	const EntryCount = buffer.readu16(Buffer, Offset)
	Offset += 2

	const Entries = {} :: { Types.ReceivedBatchPacket }

	for _ = 1, EntryCount do
		const ID = buffer.readu16(Buffer, Offset)
		Offset += 2
		const Name = IdentifierRegistry.GetNameFromID(ID)

		const ArgCount = buffer.readu8(Buffer, Offset)
		Offset += 1
		const EntrySize = buffer.readu16(Buffer, Offset)
		Offset += 2

		const Args = table.create(ArgCount) :: Types.Args
		Args.n = ArgCount

		for i = 1, ArgCount do
			const Tag = buffer.readu8(Buffer, Offset)
			Offset += 1
			const Value, NewOffset = BinaryCodec.GetReader(Tag)(Buffer, Offset, InstanceList)
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

const function ExtractFireOptions(Args: { [any]: any }): (boolean, Types.Args?)
	const n = Args.n :: number
	if not n or n <= 0 then
		return Config.Batching.BatchByDefault, Args
	end

	const options = Args[n] :: Types.BuiltFireOptions
	if typeof(options) ~= "table" or not options.__DysconnectFireOptions then
		return Config.Batching.BatchByDefault, Args
	end

	const batch: boolean = if options.Batch ~= nil then options.Batch else Config.Batching.BatchByDefault

	--this seems like an unnecessary first approach
	-- const Clean = table.create(n - 1)
	-- for i = 1, n - 1 do
	-- 	Clean[i] = Args[i]
	-- end
	const Clean = table.clone(Args)
	Clean[n] = nil
	Clean.n = n - 1
	return batch, Clean
end

return table.freeze({
	UnpackArgTable = UnpackArgTable,
	PackArgumentsForNetwork = PackArgumentsForNetwork,
	UnpackArgumentsFromNetwork = UnpackArgumentsFromNetwork,
	PackBatchEnvelope = PackBatchEnvelope,
	UnpackBatchEnvelope = UnpackBatchEnvelope,
	ExtractFireOptions = ExtractFireOptions,
	GetSizeOfBatchEvent = GetSizeOfBatchEvent,
})
