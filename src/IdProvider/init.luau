--!strict

const MinHeap = require("@self/MinHeap")

const MAX_ID = 65_535 -- 2^16 - 1

const IDs = {} :: { [string]: number }
const ReverseIDs = {} :: { [number]: string }

const FreeIds = MinHeap.new()
local NextId = 3

--[=[
	@class IdProvider
	@private
]=]
const IdProvider = {}

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

function IdProvider.Register(Object: string, IdOverride: number?): number
	const Id = IdOverride or GenerateID()

	if ReverseIDs[Id] then
		error(`ID {Id} already registered Preventing registration...`)
	end

	ReverseIDs[Id] = Object
	IDs[Object] = Id

	return Id
end

function IdProvider.Unregister(ID: number)
	const Object = ReverseIDs[ID]

	if Object == nil then
		return
	end

	ReverseIDs[ID] = nil
	IDs[Object] = nil

	FreeIds:Push(ID)
end

function IdProvider.GetObjectByID(ID: number): string?
	if not ID then
		return nil
	end

	return ReverseIDs[ID]
end

function IdProvider.GetIDByObject(Object: any): number?
	if not Object then
		return nil
	end

	return IDs[Object]
end

return IdProvider
