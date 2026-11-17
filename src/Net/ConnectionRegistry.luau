--!strict
--!optimize 2

const Types = require("../Types")

type List = { [Types.EventType]: { [string]: Types.InternalConnection } }
const List = {} :: List
const Connections = {}

local NAMING_EQUIVALENTS: { [Types.EventType]: any }

function Connections.Setup(Names: { [Types.EventType]: any })
	NAMING_EQUIVALENTS = Names
	for Name, _ in Names do
		List[Name :: Types.EventType] = {}
	end
end

function Connections.GetConnectionsByName(Type: Types.EventType, Name: string): Types.InternalConnection?
	const Typed = List[Type]
	if not Typed then
		return nil
	end
	return Typed[Name]
end

function Connections.WaitForConnectionType(Type: Types.EventType)
	if List[Type] == nil and NAMING_EQUIVALENTS and NAMING_EQUIVALENTS[Type] ~= nil then
		repeat
			task.wait()
		until List[Type]
	end
end

function Connections.Create(Type: Types.EventType, name: string, Callback: Types.Callback, Predicate: Types.Predicate?)
	if List[Type][name] == nil and Type ~= "REMOTE_FUNCTION" then
		List[Type][name] = {}
	end
	if Type == "REMOTE_FUNCTION" then
		List[Type][name] = {
			Callback = Callback :: Types.Callback,
			Predicate = Predicate,
		}
	else
		List[Type][name][Callback :: Types.Callback] = {
			Predicate = Predicate,
		}
	end
end

function Connections.Destroy()
	for _, Type in List do
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

--[=[
	@class Connection
	@__index Connection
	
	Represents a connection to a network event or function.
]=]
const Connection = {}
Connection.__index = Connection

--[=[
	@within Connection
	
	Destroys this [Connection], rendering it unusuable and setting its [Connection.Connected] property to `false`.
]=]
function Connection.Disconnect(self: Types.Connection)
	if not self.Connected then
		return
	end

	const Entry = Connections.GetConnectionsByName(self.Type :: Types.NetworkEventType, self.Name)
	if Entry then
		if self.Type == "REMOTE_FUNCTION" then
			if Entry.Callback == self.Callback then
				List[self.Type][self.Name] = nil
			end
		else
			Entry[self.Callback] = nil
		end
	end

	table.clear(self)
	self.Connected = false
	-- setmetatable(self, nil)
end
--[=[
	@function Destroy
	@within Connection
	
	Equivalent to [Connection.Disconnect].
	
	@param self Connection
]=]
Connection.Destroy = Connection.Disconnect --shortcut for compatibility

Connections.MetaConnection = Connection

table.freeze(Connection)
return table.freeze(Connections)
