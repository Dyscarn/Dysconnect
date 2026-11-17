--!strict
--!optimize 2

const IdentifierAllocator = require("../Net/IdentifierAllocator")

const function GenerateIdForName(Name: string, Override: number?): number
	return IdentifierAllocator.Register(Name, Override)
end

const function GetNameFromID(ID: number): string
	local Name = IdentifierAllocator.GetObjectByID(ID)

	if Name == nil then
		error(`[Dysconnect] Failed name discovery for ID {ID}!`)
	end

	return Name
end
const function GetIDFromName(Name: string): number
	local ID = IdentifierAllocator.GetIDByObject(Name)

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
