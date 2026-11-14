--!strict

--min heap for cool 0(log n) lookup
type MetaMinHeap = {
	__index: MetaMinHeap,
	--IsEmpty: (self: MinHeap) -> boolean,
	Push: (self: MinHeap, Value: number) -> (),
	Pop: (self: MinHeap) -> number?,
}
type MinHeap = typeof(setmetatable(
	{} :: {
		Data: { [number]: number },
	},
	{} :: {
		__index: MetaMinHeap,
	}
))

--[=[
	@class MinHeap
	@__index MinHeap
	@private
]=]
const MinHeap = {}
MinHeap.__index = MinHeap
const function new(): MinHeap
	return setmetatable({
		Data = {},
	}, MinHeap)
end

function MinHeap.Push(self: MinHeap, Value: number)
	const Data = self.Data
	table.insert(Data, Value)
	local Index = #Data

	while Index > 1 do
		const Parent = math.floor(Index / 2)

		if Data[Parent] <= Data[Index] then
			break
		end

		--reversing the values in a very hacky way
		Data[Parent], Data[Index] = Data[Index], Data[Parent]

		Index = Parent
	end
end

function MinHeap.Pop(self: MinHeap): number?
	const Data = self.Data
	local Size = #Data

	if Size == 0 then
		return nil
	end

	const Root = Data[1]

	if Size == 1 then
		Data[1] = nil
		return Root
	end

	Data[1] = Data[Size]
	Data[Size] = nil

	Size -= 1
	local Index = 1

	while true do
		const Left = Index * 2
		const Right = Left + 1
		local Smallest = Index

		if Left <= Size and Data[Left] < Data[Smallest] then
			Smallest = Left
		end

		if Right <= Size and Data[Right] < Data[Smallest] then
			Smallest = Right
		end

		if Smallest == Index then
			break
		end

		Data[Index], Data[Smallest] = Data[Smallest], Data[Index]

		Index = Smallest
	end

	return Root
end

return {
	new = new,
}
