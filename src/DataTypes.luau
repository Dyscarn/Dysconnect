--i would comment this but i already wrote a whole commented DataTypes module that didn't do shit to optimize networking so now i'm too lazy to comment its entirety again
--figure out what's here i'm done 😭 -dys

--!strict
--!native

const HttpService = game:GetService("HttpService")

const DataTypes = {
	Enum = {
		NIL = 0,
		boolean = 1,
		Int8 = 2,
		Int16 = 3,
		Int32 = 4,
		Float32 = 5,
		Float64 = 6,
		Vector3 = 7,
		JSON = 8,
		buffer = 9,
		string = 10,
		CFrame = 11,
		Vector2 = 12,
		Color3 = 13,
		UDim2 = 14,
		BrickColor = 15,
		Rect = 16,
		NumberRange = 17,
		UDim = 18,
		DateTime = 19,
		ColorSequence = 20,
		NumberSequence = 21,
		TweenInfo = 22,
		Instance = 23,
		Map = 24,
	},
}

--setting the size of every type beforehand to not have to calculate it unless it's necessary
const FixedSizes = {
	[DataTypes.Enum.NIL] = 0,
	[DataTypes.Enum.boolean] = 1,
	[DataTypes.Enum.Int8] = 1,
	[DataTypes.Enum.Int16] = 2,
	[DataTypes.Enum.Int32] = 4,
	[DataTypes.Enum.Float32] = 4,
	[DataTypes.Enum.Float64] = 8,
	[DataTypes.Enum.Vector3] = 12,
	[DataTypes.Enum.CFrame] = 28,
	[DataTypes.Enum.Vector2] = 8,
	[DataTypes.Enum.Color3] = 12,
	[DataTypes.Enum.UDim2] = 16,
	[DataTypes.Enum.BrickColor] = 2,
	[DataTypes.Enum.Rect] = 16,
	[DataTypes.Enum.NumberRange] = 8,
	[DataTypes.Enum.UDim] = 8,
	[DataTypes.Enum.DateTime] = 8,
	[DataTypes.Enum.TweenInfo] = 16,
	[DataTypes.Enum.Instance] = 2,
}

--tweeninfo stuffs
const StyleMap = {}
for _, enumItem in Enum.EasingStyle:GetEnumItems() do
	StyleMap[enumItem.Value] = enumItem
end

const DirectionMap = {}
for _, enumItem in Enum.EasingDirection:GetEnumItems() do
	DirectionMap[enumItem.Value] = enumItem
end

const function DeepFreezeTable<T>(Target: T & {}): T & {} --if all tables are frozen it'll allow the engine to optimize data access since you can't really write on any tables
	for _Name, Member in Target :: { any } do
		if typeof(Member) == "table" then
			DeepFreezeTable(Member)
		end
	end

	return table.freeze(Target)
end

const function IsNumberAnInt(Value: number): boolean
	return Value % 1 == 0 --if the remainder of the number divided by 1 is 0 then there's no decimal remainder for the number therefore it's an int
end

const function IsNumberBetweenBounds(Value: number, Minimum: number, Maximum: number): boolean
	return Value >= Minimum and Value <= Maximum
end

const function IsNumberAnInt8(Value: number): boolean
	return IsNumberBetweenBounds(Value, -128, 127) -- signed:  -(2^8) / 2 ; (2^8) / 2 - 1
end

const function IsNumberAnInt16(Value: number): boolean
	return IsNumberBetweenBounds(Value, -32_768, 32_767) -- signed:  -(2^16) / 2 ; (2^16) / 2 - 1
end

const function IsNumberAnInt32(Value: number): boolean
	return IsNumberBetweenBounds(Value, -2_147_483_648, 2_147_483_647) -- signed:  -(2^32) / 2 ; (2^32) / 2 - 1
end

const function IsHighPrecisionFloat(value: number): boolean
	return math.abs(value) > 1e4 or (value % 1 ~= 0 and value * 1000 % 1 ~= 0)
end

function DataTypes.GetTagFromValue(Value: any): number
	if Value == nil then
		return DataTypes.Enum.NIL
	end

	const Type = typeof(Value)

	if DataTypes.Enum[Type] then
		return DataTypes.Enum[Type]
	end

	if Type == "number" then
		if not IsNumberAnInt(Value) then
			if IsHighPrecisionFloat(Value) then
				return DataTypes.Enum.Float64
			end

			return DataTypes.Enum.Float32
		end

		if IsNumberAnInt8(Value) then
			return DataTypes.Enum.Int8
		end

		if IsNumberAnInt16(Value) then
			return DataTypes.Enum.Int16
		end

		if IsNumberAnInt32(Value) then
			return DataTypes.Enum.Int32
		end

		if IsHighPrecisionFloat(Value) then
			return DataTypes.Enum.Float64
		end

		return DataTypes.Enum.Float32
	end

	if Type == "table" then
		return DataTypes.Enum.Map
	end

	return DataTypes.Enum.JSON
end

function DataTypes.GetPayloadSize(tag: number, value: any): number
	--if it has a fixed size, return that
	if FixedSizes[tag] then
		return FixedSizes[tag]
	end

	if tag == DataTypes.Enum.Map then
		--yuh you kinda get the point
		--iterate through every item blah blah add their size to the total blah blah BORING.
		local total = 2
		for Key, Value in value do
			const KeyTag = DataTypes.GetTagFromValue(Key)
			const ValueTag = DataTypes.GetTagFromValue(Value)

			total += (1 + DataTypes.GetPayloadSize(KeyTag, Key))
			total += (1 + DataTypes.GetPayloadSize(ValueTag, Value))
		end
		return total
	end

	if tag == DataTypes.Enum.string then
		return 4 + #value
	elseif tag == DataTypes.Enum.JSON then
		const encoded = HttpService:JSONEncode(value)
		return 4 + #encoded
	elseif tag == DataTypes.Enum.buffer then
		return 4 + buffer.len(value)
	elseif tag == DataTypes.Enum.ColorSequence then
		return 1 + (#value.Keypoints * 16)
	elseif tag == DataTypes.Enum.NumberSequence then
		return 1 + (#value.Keypoints * 12)
	end

	return 0 --fallback even if it isn't possible to get here (fuck you selene!!!!!)
end

DataTypes.Writers = {
	[DataTypes.Enum.NIL] = function(_Buffer: buffer, Count: number, _Value: boolean): number
		return Count
	end,

	[DataTypes.Enum.boolean] = function(Buffer: buffer, Count: number, Value: boolean): number
		buffer.writeu8(Buffer, Count, Value and 1 or 0)
		return Count + 1
	end,

	[DataTypes.Enum.Int8] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writei8(Buffer, Count, Value)
		return Count + 1
	end,

	[DataTypes.Enum.Int16] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writei16(Buffer, Count, Value)
		return Count + 2
	end,

	[DataTypes.Enum.Int32] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writei32(Buffer, Count, Value)
		return Count + 4
	end,

	[DataTypes.Enum.Float32] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writef32(Buffer, Count, Value)
		return Count + 4
	end,

	[DataTypes.Enum.Float64] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writef64(Buffer, Count, Value)
		return Count + 8
	end,

	[DataTypes.Enum.Vector3] = function(Buffer: buffer, Count: number, Value: Vector3): number
		buffer.writef32(Buffer, Count, Value.X)
		buffer.writef32(Buffer, Count + 4, Value.Y)
		buffer.writef32(Buffer, Count + 8, Value.Z)
		return Count + 12
	end,

	[DataTypes.Enum.JSON] = function(Buffer: buffer, Count: number, Value: any): number
		const encoded = HttpService:JSONEncode(Value)
		const len = #encoded
		buffer.writeu32(Buffer, Count, len)
		buffer.writestring(Buffer, Count + 4, encoded)
		return Count + 4 + len
	end,

	[DataTypes.Enum.buffer] = function(Buffer: buffer, Count: number, Value: buffer): number
		const len = buffer.len(Value)
		buffer.writeu32(Buffer, Count, len)
		buffer.copy(Buffer, Count + 4, Value, 0, len)
		return Count + 4 + len
	end,

	[DataTypes.Enum.string] = function(Buffer: buffer, Count: number, Value: string): number
		const len = #Value
		buffer.writeu32(Buffer, Count, len)
		buffer.writestring(Buffer, Count + 4, Value)
		return Count + 4 + len
	end,

	[DataTypes.Enum.CFrame] = function(Buffer: buffer, Count: number, Value: CFrame): number
		const pos = Value.Position
		const axis, angle = Value:ToAxisAngle()

		--position
		buffer.writef32(Buffer, Count, pos.X)
		buffer.writef32(Buffer, Count + 4, pos.Y)
		buffer.writef32(Buffer, Count + 8, pos.Z)

		--rotation axis
		buffer.writef32(Buffer, Count + 12, axis.X)
		buffer.writef32(Buffer, Count + 16, axis.Y)
		buffer.writef32(Buffer, Count + 20, axis.Z)

		--rotation angle
		buffer.writef32(Buffer, Count + 24, angle)

		return Count + 28
	end,

	[DataTypes.Enum.Vector2] = function(Buffer: buffer, Count: number, Value: Vector2): number
		buffer.writef32(Buffer, Count, Value.X)
		buffer.writef32(Buffer, Count + 4, Value.Y)
		return Count + 8
	end,

	[DataTypes.Enum.Color3] = function(Buffer: buffer, Count: number, Value: Color3): number
		buffer.writef32(Buffer, Count, Value.R)
		buffer.writef32(Buffer, Count + 4, Value.G)
		buffer.writef32(Buffer, Count + 8, Value.B)
		return Count + 12
	end,

	[DataTypes.Enum.UDim2] = function(Buffer: buffer, Count: number, Value: UDim2): number
		buffer.writef32(Buffer, Count, Value.X.Scale)
		buffer.writei32(Buffer, Count + 4, Value.X.Offset)
		buffer.writef32(Buffer, Count + 8, Value.Y.Scale)
		buffer.writei32(Buffer, Count + 12, Value.Y.Offset)
		return Count + 16
	end,

	[DataTypes.Enum.BrickColor] = function(Buffer: buffer, Count: number, Value: BrickColor): number
		buffer.writeu16(Buffer, Count, Value.Number)
		return Count + 2
	end,

	[DataTypes.Enum.Rect] = function(Buffer: buffer, Count: number, Value: Rect): number
		buffer.writef32(Buffer, Count, Value.Min.X)
		buffer.writef32(Buffer, Count + 4, Value.Min.Y)
		buffer.writef32(Buffer, Count + 8, Value.Max.X)
		buffer.writef32(Buffer, Count + 12, Value.Max.Y)
		return Count + 16
	end,

	[DataTypes.Enum.NumberRange] = function(Buffer: buffer, Count: number, Value: NumberRange): number
		buffer.writef32(Buffer, Count, Value.Min)
		buffer.writef32(Buffer, Count + 4, Value.Max)
		return Count + 8
	end,

	[DataTypes.Enum.UDim] = function(Buffer: buffer, Count: number, Value: UDim): number
		buffer.writef32(Buffer, Count, Value.Scale)
		buffer.writei32(Buffer, Count + 4, Value.Offset)
		return Count + 8
	end,

	[DataTypes.Enum.DateTime] = function(Buffer: buffer, Count: number, Value: DateTime): number
		buffer.writef64(Buffer, Count, Value.UnixTimestamp)
		return Count + 8
	end,

	[DataTypes.Enum.ColorSequence] = function(Buffer: buffer, Count: number, Value: ColorSequence): number
		const keypoints = Value.Keypoints
		const count = #keypoints
		buffer.writeu8(Buffer, Count, count)
		Count += 1
		for _, kp in keypoints do
			buffer.writef32(Buffer, Count, kp.Time)
			buffer.writef32(Buffer, Count + 4, kp.Value.R)
			buffer.writef32(Buffer, Count + 8, kp.Value.G)
			buffer.writef32(Buffer, Count + 12, kp.Value.B)
			Count += 16
		end
		return Count
	end,

	[DataTypes.Enum.NumberSequence] = function(Buffer: buffer, Count: number, Value: NumberSequence): number
		const keypoints = Value.Keypoints
		const count = #keypoints
		buffer.writeu8(Buffer, Count, count)
		Count += 1
		for _, kp in keypoints do
			buffer.writef32(Buffer, Count, kp.Time)
			buffer.writef32(Buffer, Count + 4, kp.Value)
			buffer.writef32(Buffer, Count + 8, kp.Envelope)
			Count += 12
		end
		return Count
	end,

	[DataTypes.Enum.TweenInfo] = function(Buffer: buffer, Count: number, Value: TweenInfo): number
		buffer.writef32(Buffer, Count, Value.Time)
		buffer.writeu8(Buffer, Count + 4, Value.EasingStyle.Value)
		buffer.writeu8(Buffer, Count + 5, Value.EasingDirection.Value)
		buffer.writei32(Buffer, Count + 6, Value.RepeatCount)
		buffer.writeu8(Buffer, Count + 10, Value.Reverses and 1 or 0)
		buffer.writef32(Buffer, Count + 11, Value.DelayTime)

		return Count + 16
	end,

	[DataTypes.Enum.Instance] = function(Buffer: buffer, Count: number, Value: Instance, InstanceList: { Instance }): number
		table.insert(InstanceList, Value)
		const Length = #InstanceList

		buffer.writeu16(Buffer, Count, Length)
		return Count + 2
	end,

	[DataTypes.Enum.Map] = function(Buffer: buffer, Count: number, Value: { any }, InstanceList: { Instance }): number
		--not using utils here just in case i wanna reuse this for a different game
		local TableCount = 0
		for _, _ in Value do
			TableCount += 1
		end

		buffer.writeu16(Buffer, Count, TableCount) --write le count
		Count += 2

		const Writers = DataTypes.Writers

		for key, val in Value do
			const KeyTag = DataTypes.GetTagFromValue(key)
			const ValueTag = DataTypes.GetTagFromValue(val)

			--write le key
			buffer.writeu8(Buffer, Count, KeyTag)
			Count += 1
			Count = Writers[KeyTag](Buffer, Count, key, InstanceList)

			--write le value after le key
			buffer.writeu8(Buffer, Count, ValueTag)
			Count += 1
			Count = Writers[ValueTag](Buffer, Count, val, InstanceList)
		end

		return Count
	end,
} :: { [number]: (Buffer: buffer, Count: number, Value: any, InstanceList: { Instance }) -> number }

DataTypes.Readers = {
	[DataTypes.Enum.NIL] = function(_Buffer: buffer, Count: number): (nil, number)
		return nil, Count
	end,

	[DataTypes.Enum.boolean] = function(Buffer: buffer, Count: number): (boolean, number)
		return buffer.readu8(Buffer, Count) == 1, Count + 1
	end,

	[DataTypes.Enum.Int8] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readi8(Buffer, Count), Count + 1
	end,

	[DataTypes.Enum.Int16] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readi16(Buffer, Count), Count + 2
	end,

	[DataTypes.Enum.Int32] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readi32(Buffer, Count), Count + 4
	end,

	[DataTypes.Enum.Float32] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readf32(Buffer, Count), Count + 4
	end,

	[DataTypes.Enum.Float64] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readf64(Buffer, Count), Count + 8
	end,

	[DataTypes.Enum.Vector3] = function(Buffer: buffer, Count: number): (Vector3, number)
		return Vector3.new(buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4), buffer.readf32(Buffer, Count + 8)), Count + 12
	end,

	[DataTypes.Enum.JSON] = function(Buffer: buffer, Count: number): any
		const len = buffer.readu32(Buffer, Count)
		const content = buffer.readstring(Buffer, Count + 4, len)
		return HttpService:JSONDecode(content), Count + 4 + len
	end,

	[DataTypes.Enum.buffer] = function(Buffer: buffer, Count: number): (buffer, number)
		const len = buffer.readu32(Buffer, Count)
		const newBuf = buffer.create(len)
		buffer.copy(newBuf, 0, Buffer, Count + 4, len)
		return newBuf, Count + 4 + len
	end,

	[DataTypes.Enum.string] = function(Buffer: buffer, Count: number): (string, number)
		const len = buffer.readu32(Buffer, Count)
		return buffer.readstring(Buffer, Count + 4, len), Count + 4 + len
	end,

	[DataTypes.Enum.CFrame] = function(Buffer: buffer, Count: number): (CFrame, number)
		const px, py, pz = buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4), buffer.readf32(Buffer, Count + 8)
		const ax, ay, az = buffer.readf32(Buffer, Count + 12), buffer.readf32(Buffer, Count + 16), buffer.readf32(Buffer, Count + 20)
		const ang = buffer.readf32(Buffer, Count + 24)
		const pos = Vector3.new(px, py, pz)
		const axis = Vector3.new(ax, ay, az)
		if ang == 0 then
			return CFrame.new(pos), Count + 28
		end
		return CFrame.fromAxisAngle(axis, ang) + pos, Count + 28
	end,

	[DataTypes.Enum.Vector2] = function(Buffer: buffer, Count: number): (Vector2, number)
		return Vector2.new(buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4)), Count + 8
	end,

	[DataTypes.Enum.Color3] = function(Buffer: buffer, Count: number): (Color3, number)
		return Color3.new(buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4), buffer.readf32(Buffer, Count + 8)), Count + 12
	end,

	[DataTypes.Enum.UDim2] = function(Buffer: buffer, Count: number): (UDim2, number)
		return UDim2.new(buffer.readf32(Buffer, Count), buffer.readi32(Buffer, Count + 4), buffer.readf32(Buffer, Count + 8), buffer.readi32(Buffer, Count + 12)), Count + 16
	end,

	[DataTypes.Enum.BrickColor] = function(Buffer: buffer, Count: number): (BrickColor, number)
		return BrickColor.new(buffer.readu16(Buffer, Count)), Count + 2
	end,

	[DataTypes.Enum.Rect] = function(Buffer: buffer, Count: number): (Rect, number)
		return Rect.new(buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4), buffer.readf32(Buffer, Count + 8), buffer.readf32(Buffer, Count + 12)), Count + 16
	end,

	[DataTypes.Enum.NumberRange] = function(Buffer: buffer, Count: number): (NumberRange, number)
		return NumberRange.new(buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4)), Count + 8
	end,

	[DataTypes.Enum.UDim] = function(Buffer: buffer, Count: number): (UDim, number)
		return UDim.new(buffer.readf32(Buffer, Count), buffer.readi32(Buffer, Count + 4)), Count + 8
	end,

	[DataTypes.Enum.DateTime] = function(Buffer: buffer, Count: number): (DateTime, number)
		return DateTime.fromUnixTimestamp(buffer.readf64(Buffer, Count)), Count + 8
	end,

	[DataTypes.Enum.ColorSequence] = function(Buffer: buffer, Count: number): (ColorSequence, number)
		const count = buffer.readu8(Buffer, Count)
		Count += 1
		const keypoints = {}
		for _ = 1, count do
			const Time = buffer.readf32(Buffer, Count)
			const r, g, b = buffer.readf32(Buffer, Count + 4), buffer.readf32(Buffer, Count + 8), buffer.readf32(Buffer, Count + 12)
			table.insert(keypoints, ColorSequenceKeypoint.new(Time, Color3.new(r, g, b)))
			Count += 16
		end
		return ColorSequence.new(keypoints), Count
	end,

	[DataTypes.Enum.NumberSequence] = function(Buffer: buffer, Count: number): (NumberSequence, number)
		const count = buffer.readu8(Buffer, Count)
		Count += 1
		const keypoints = {}
		for _ = 1, count do
			const t = buffer.readf32(Buffer, Count)
			const Value = buffer.readf32(Buffer, Count + 4)
			const env = buffer.readf32(Buffer, Count + 8)
			table.insert(keypoints, NumberSequenceKeypoint.new(t, Value, env))
			Count += 12
		end
		return NumberSequence.new(keypoints), Count
	end,

	[DataTypes.Enum.TweenInfo] = function(Buffer: buffer, Count: number): (TweenInfo, number)
		const Time = buffer.readf32(Buffer, Count)
		const StyleId = buffer.readu8(Buffer, Count + 4)
		const DirectionId = buffer.readu8(Buffer, Count + 5)
		const count = buffer.readi32(Buffer, Count + 6)
		const reverses = buffer.readu8(Buffer, Count + 10) == 1
		const Delay = buffer.readf32(Buffer, Count + 11)

		const style = StyleMap[StyleId] or Enum.EasingStyle.Linear
		const dir = DirectionMap[DirectionId] or Enum.EasingDirection.Out

		return TweenInfo.new(Time, style, dir, count, reverses, Delay), Count + 16
	end,

	[DataTypes.Enum.Instance] = function(Buffer: buffer, Count: number, InstanceList: { Instance }): (Instance?, number)
		const index = buffer.readu16(Buffer, Count)
		const inst = InstanceList and InstanceList[index] or nil
		return inst, Count + 2
	end,

	[DataTypes.Enum.Map] = function(Buffer: buffer, Count: number, InstanceList: { Instance }): ({ any }, number)
		const count = buffer.readu16(Buffer, Count)
		Count += 2

		const Readers = DataTypes.Readers

		const Table = {}
		for _ = 1, count do
			--read le key
			const KeyTag = buffer.readu8(Buffer, Count)
			Count += 1
			local Key
			Key, Count = Readers[KeyTag](Buffer, Count, InstanceList)

			--read le value
			const ValueTag = buffer.readu8(Buffer, Count :: any)
			Count += 1
			local Value
			Value, Count = Readers[ValueTag](Buffer, Count, InstanceList)

			--set the damn thing
			Table[Key] = Value
		end

		return Table, Count
	end,
} :: { (Buffer: buffer, Count: number, InstanceList: { Instance }) -> (any, number) }

return DeepFreezeTable(DataTypes)
