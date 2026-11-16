--!strict

--[=[
	@class Types
	
	Contains almost every type of Dysconnect.
]=]

--[=[
	@type Callback ((...any) -> any) | ((Player: Player, ...any) -> any) | ((...any) -> ()) | ((Player: Player, ...any) -> ())
	@within Types
]=]
export type Callback = ((...any) -> any) | ((Player: Player, ...any) -> any) | ((...any) -> ()) | ((Player: Player, ...any) -> ())
--[=[
	@type Predicate ((...any) -> boolean) | ((Player: Player, ...any) -> boolean)
	@within Types
	
	Function containing sanity checks to execute a callback afterwards if it returns `true`.
]=]
export type Predicate = ((...any) -> boolean) | ((Player: Player, ...any) -> boolean)

--[=[
	@type RemoteType "REMOTE_EVENT" | "UREMOTE_EVENT"
	@within Types
	
	Event types that go over the network and don't return anything.
]=]
export type RemoteType = "REMOTE_EVENT" | "UREMOTE_EVENT"
--[=[
	@type NetworkEventType RemoteType | "BINDABLE_EVENT"
	@within Types
	
	Event types that do and don't go over the network but don't return anything.
]=]
export type NetworkEventType = RemoteType | "BINDABLE_EVENT"
--[=[
	@type InvokableType RemoteType | "REMOTE_FUNCTION"
	@within Types
	
	Event types that go over the network that do and don't return anything.
]=]
export type InvokableType = RemoteType | "REMOTE_FUNCTION"
--[=[
	@type EventType RemoteType | NetworkEventType | InvokableType
	@within Types
	
	All supported event and function types in Types.
]=]
export type EventType = RemoteType | NetworkEventType | InvokableType

export type InternalConnection = {
	Callback: Callback?,
	Predicate: Predicate?,
	[Callback]: {
		Predicate: Predicate?,
	}?,
}

--[=[
	@interface Connection
	@within Connection
	
	.Connected boolean -- If this [Connection] is still bound to its event.
	.Type EventType -- The type of event it's connected to.
	.Name string -- The name of the event it's connected to.
	.Callback Callback -- The callback that'll execute when this connection receives a signal.
]=]
export type Connection = typeof(setmetatable(
	{} :: {
		Connected: boolean,
		Type: EventType,
		Name: string,
		Callback: Callback,
	},
	{} :: {
		Disconnect: (self: Connection) -> (),
		Destroy: (self: Connection) -> (),
	}
))

--[=[
	@interface BatchPacket
	@within Types
	@private
	
	Queued packet for batching in a frame.
	
	.EventName string -- The name of the target event.
	.Args { [number]: any } -- The arguments to pass to the event.
]=]
export type BatchPacket = {
	EventName: string,
	Args: Args,
}
--[=[
	@interface TargetedBatchPacket
	@within Types
	@private
	
	Queued packet for batching in a frame, targeted to one or more [Player]s.
	
	.Base BatchPacket -- Contains all fields from [BatchPacket]. This doesn't mean this has a field called "Base".
	.EventType RemoteType -- The type of event to fire.
	.Target (Player | { Player })? -- The player/s to fire the event to.
]=]
export type TargetedBatchPacket = BatchPacket & {
	Target: (Player | "All")?,
	EventType: RemoteType,
}
export type ReceivedBatchPacket = BatchPacket

--[=[
	@interface FireOptions
	@within Types
	
	Options for a specific remote call.
	
	.Batch boolean? -- If this remote call will be batch. Overrides [BATCHING.BatchByDefault].
]=]
export type FireOptions = {
	Batch: boolean?,
}
export type BuiltFireOptions = FireOptions & {
	__DysconnectFireOptions: true,
}

export type Args = {
	n: number,
	[number]: any,
}

return table.freeze({})
