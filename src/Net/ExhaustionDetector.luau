--!strict
--!optimize 2

const Players = game:GetService("Players")

const Config = require("../Config")

local Stamp = workspace:GetServerTimeNow()
const function Time(): number
	return workspace:GetServerTimeNow() - (Stamp :: number)
end

const ExhaustionDetector = {}
const Logs = {} :: { [number]: {
	Total: number,
	Last: number,
} }

function ExhaustionDetector.Setup()
	Players.PlayerRemoving:Connect(function(Player: Player)
		--cleanup
		Logs[Player.UserId] = nil
	end)
end

function ExhaustionDetector.CheckPlayerRateLimit(Player: Player, EventType: "RemoteEvent" | "RemoteFunction" | "UnreliableRemoteEvent"): boolean
	if EventType == "UnreliableRemoteEvent" and Config.Authority.URemoteEventRateIncreaseMult <= 0 then
		return true
	end

	const Now = Time()

	if not Logs[Player.UserId] then
		Logs[Player.UserId] = { Total = 0, Last = Now }
	end

	const Data = Logs[Player.UserId]

	const Elapsed = Now - Data.Last
	--check how many remotes it's fired before the second passes
	const Used = Elapsed * Config.Authority.RateDropPerSecond

	Data.Total = math.max(0, Data.Total - Used)
	Data.Last = Now

	--check if it exceeds the limit
	if Data.Total >= Config.Authority.RateLimit then
		return false
	end

	Data.Total += EventType == "UnreliableRemoteEvent" and Config.Authority.URemoteEventRateIncreaseMult or 1

	return true
end

return table.freeze(ExhaustionDetector)
