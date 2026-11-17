--!strict
--!optimize 2

const MinHeap = require("@self/MinHeap")

const MAX_ID = 65_535 -- 2^16 - 1

const IDs = {} :: { [string]: number }
const ReverseIDs = {} :: { [number]: string }

const FreeIds = MinHeap.new()
local NextId = 3

--[=[
	@class IdAllocator
	@private
]=]
const IdAllocator = {}

const function GenerateID(): number
	--reuse lowest free ids
	const ReusedId = FreeIds:Pop()

	if ReusedId then
		return ReusedId
	end

	if NextId > MAX_ID then
		error("No IDs available!")
	end

	const Id = NextId
	NextId += 1

	return Id
end

function IdAllocator.Register(Object: string, IdOverride: number?): number
	const Id = IdOverride or GenerateID()

	if ReverseIDs[Id] then
		if ReverseIDs[Id] == Object then
			return Id
		end
		error(`ID {Id} already registered! Preventing registration...`)
	end

	if IDs[Object] then
		if IDs[Object] == Id then
			return Id
		end
		error(`Name "{Object}" already registered with ID {IDs[Object]}! Preventing registration...`)
	end

	ReverseIDs[Id] = Object
	IDs[Object] = Id

	return Id
end

function IdAllocator.Unregister(ID: number)
	const Object = ReverseIDs[ID]

	if Object == nil then
		return
	end

	ReverseIDs[ID] = nil
	IDs[Object] = nil

	FreeIds:Push(ID)
end

function IdAllocator.GetObjectByID(ID: number): string?
	if not ID then
		return nil
	end

	return ReverseIDs[ID]
end

function IdAllocator.GetIDByObject(Object: any): number?
	if not Object then
		return nil
	end

	return IDs[Object]
end

function IdAllocator.GetIdObjects(): { [number]: string }
	return ReverseIDs
end

function IdAllocator.GetObjectIds(): { [string]: number }
	return IDs
end

return table.freeze(IdAllocator)
