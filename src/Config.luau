--!strict

--[=[
	@class Config
	
	Configuration container for Dysconnect.
]=]
const Config = {
	--[=[
		@interface Debug
		@within Dysconnect
		
		Debug print statement toggles.
		
		Modifiable in the network script or in [Dysconnect.Init].	
		
		.QueuedPackets boolean -- Prints info whenever a packet is added to the batch queue (including name, type and size in bytes).
		.ReceivedPackets boolean -- Prints info whenever a packet is received on either side (including name, type and size in bytes).
		.SentPackets boolean -- Prints info whenever a packet is sent from either side (including name and type).
		.RateLimitExceeded boolean -- Prints info whenever a [Player] exceeds its rate limit, thus dropping the packets it sends (includes name and [Player.UserId]).
		.ExcludeUnreliable boolean -- If `true`, will exclude [UnreliableRemoteEvent] send & receive prints (from [DEBUG.ReceivedPackets] and [DEBUG.SentPackets]).
		.ExcludeReserved boolean -- If `true`, will exclude prints of events that are reserved internally by Dysconnect.
		.Strict boolean -- Prints a warn if an object of a type not supported by Dysconnect is trying to be sent over the network, falling back to JSON.
	]=]
	Debug = table.freeze({
		QueuedPackets = true,
		ReceivedPackets = true,
		SentPackets = false,
		RateLimitExceeded = true,
		ExcludeUnreliable = true,
		ExcludeReserved = true,
		Strict = true,
	}),
	--[=[
		@interface Authority
		@within Dysconnect
		
		Configuration for per-player network exhaustion detection.
		Tracks incoming remote calls and gradually reduces the accumulated
		usage over time to limit excessive requests.
		
		Modifiable in the network script or in [Dysconnect.Init].
		
		.AllowJsonFromClients boolean -- If the server should accept JSON arguments from events. This is important as they're large and slow to process.
		.RateLimit number -- Maximum accumulated usage before requests are rejected.
		.RateDropPerSecond number -- Rate at which accumulated usage decays per second.
		.URemoteEventRateIncreaseMult number -- Amount of usage added by each [UnreliableRemoteEvent] call.
	]=]
	Authority = table.freeze({
		AllowJsonFromClients = true,
		RateLimit = 50,
		RateDropPerSecond = 18,
		URemoteEventRateIncreaseMult = 0,
	}),
	--[=[
		@interface Batching
		@within Dysconnect
		
		Configuration for event batching, to not fire a lot of remote calls in a single frame.
		Limited at a batch size cap in KB to not produce lag spikes every time a big event
		with a lot of remote calls fires in a single frame, equivalent to firing a LOT of remotes
		in the same timespan, which is an issue.
		
		Modifiable in the network script or in [Dysconnect.Init].
		
		.BatchByDefault boolean -- If remote calls will be batched by default, since you might not want this sometimes.
		.MaxBatchSize number -- The maximum packet size of a single frame's batch, in KB.
	]=]
	Batching = table.freeze({
		BatchByDefault = true,
		MaxBatchSize = 16, --KB
	}),
}

--[=[
	@interface InitConfig
	@within Dysconnect
	
	Configurations to apply to the network service when initializing.
	
	.DebugConfig Debug -- Read [Debug].
	.AuthorityConfig Authority -- Read [Authority].
	.Batching Batching -- Read [Batching].
]=]
export type InitConfig = {
	DebugConfig: typeof(Config.Debug)?,
	AuthorityConfig: typeof(Config.Authority)?,
	Batching: typeof(Config.Batching)?,
}

return Config
