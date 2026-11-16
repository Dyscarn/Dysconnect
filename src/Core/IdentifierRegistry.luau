--!strict
--!optimize 2

const RunService = game:GetService("RunService")

const IdAllocator = require("../Net/IdAllocator")

const IS_SERVER = RunService:IsServer()

const function GenerateIdForName(Name: string, Override: number?): number
	if IS_SERVER then
		return IdAllocator.Register(Name, Override)
	end

	return Override or -1
end

const function GetNameFromID(ID: number): string
	local Name = IdAllocator.GetObjectByID(ID)

	if Name == nil then
		error(`[Dysconnect] Failed name discovery for ID {ID}!`)
	end

	return Name
end
const function GetIDFromName(Name: string): number
	local ID = IdAllocator.GetIDByObject(Name)

	if ID == nil then
		error(`[Dysconnect] Failed name discovery for name "{Name}"!`)
	end

	return ID
end

return table.freeze({
	GenerateIdForName = GenerateIdForName,
	GetNameFromID = GetNameFromID,
	GetIDFromName = GetIDFromName,
})
