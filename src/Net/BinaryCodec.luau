--i would comment this but i already wrote a whole commented BinaryCodec module that didn't do shit to optimize networking so now i'm too lazy to comment its entirety again
--figure out what's here i'm done 😭 -dys

--!strict
--!optimize 2
--!native

const HttpService = game:GetService("HttpService")

const EPSILON = 1e-5

--common tags on their own var
const TAG_NIL = 0
const TAG_FALSE = 1
const TAG_TRUE = 2
const TAG_INT8 = 3
const TAG_INT16 = 4
const TAG_INT32 = 5
const TAG_FLOAT32 = 6
const TAG_FLOAT64 = 7
const TAG_VECTOR3 = 8
const TAG_JSON = 9
const TAG_BUFFER = 10
const TAG_STRING = 11
const TAG_CFRAME = 12
const TAG_VECTOR2 = 13
const TAG_COLOR3 = 14
const TAG_UDIM2 = 15
const TAG_BRICKCOLOR = 16
const TAG_RECT = 17
const TAG_NUMBERRANGE = 18
const TAG_UDIM = 19
const TAG_DATETIME = 20
const TAG_COLORSEQUENCE = 21
const TAG_NUMBERSEQUENCE = 22
const TAG_TWEENINFO = 23
const TAG_INSTANCE = 24
const TAG_MAP = 25
const TAG_VECTOR2INT16 = 26
const TAG_VECTOR3INT16 = 27
const TAG_LONGSTRING = 28
const TAG_ARRAY = 29
const TAG_LONGERSTRING = 30
const TAG_UINT8 = 31
const TAG_UINT16 = 32
const TAG_UINT32 = 33
const TAG_CFRAMEPOS = 34

const BinaryCodec = {
	Enum = {
		NIL = TAG_NIL,
		False = TAG_FALSE,
		True = TAG_TRUE,
		Int8 = TAG_INT8,
		Int16 = TAG_INT16,
		Int32 = TAG_INT32,
		Float32 = TAG_FLOAT32,
		Float64 = TAG_FLOAT64,
		Vector3 = TAG_VECTOR3,
		JSON = TAG_JSON,
		buffer = TAG_BUFFER,
		string = TAG_STRING,
		CFrame = TAG_CFRAME,
		Vector2 = TAG_VECTOR2,
		Color3 = TAG_COLOR3,
		UDim2 = TAG_UDIM2,
		BrickColor = TAG_BRICKCOLOR,
		Rect = TAG_RECT,
		NumberRange = TAG_NUMBERRANGE,
		UDim = TAG_UDIM,
		DateTime = TAG_DATETIME,
		ColorSequence = TAG_COLORSEQUENCE,
		NumberSequence = TAG_NUMBERSEQUENCE,
		TweenInfo = TAG_TWEENINFO,
		Instance = TAG_INSTANCE,
		Map = TAG_MAP,
		Vector2int16 = TAG_VECTOR2INT16,
		Vector3int16 = TAG_VECTOR3INT16,
		LongString = TAG_LONGSTRING,
		Array = TAG_ARRAY,
		LongerString = TAG_LONGERSTRING,
		UInt8 = TAG_UINT8,
		UInt16 = TAG_UINT16,
		UInt32 = TAG_UINT32,
		CFramePos = TAG_CFRAMEPOS,
	} :: { [string]: number },
}

const ENUM = BinaryCodec.Enum

--setting the size of every type beforehand to not have to calculate it unless it's necessary
const FIXED_SIZES = table.freeze({
	[TAG_NIL] = 0,
	[TAG_TRUE] = 0,
	[TAG_FALSE] = 0,
	[TAG_INT8] = 1,
	[TAG_INT16] = 2,
	[TAG_INT32] = 4,
	[TAG_FLOAT32] = 4,
	[TAG_FLOAT64] = 8,
	[TAG_VECTOR3] = 12,
	[TAG_CFRAME] = 28,
	[TAG_VECTOR2] = 8,
	[TAG_COLOR3] = 12,
	[TAG_UDIM2] = 16,
	[TAG_BRICKCOLOR] = 2,
	[TAG_RECT] = 16,
	[TAG_NUMBERRANGE] = 8,
	[TAG_UDIM] = 8,
	[TAG_DATETIME] = 4,
	[TAG_TWEENINFO] = 15,
	[TAG_INSTANCE] = 2,
	[TAG_VECTOR2INT16] = 4,
	[TAG_VECTOR3INT16] = 6,
	[TAG_UINT8] = 1,
	[TAG_UINT16] = 2,
	[TAG_UINT32] = 4,
	[TAG_CFRAMEPOS] = 12,
}) :: { number }

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

const function IsArray(Value: { any }): boolean
	const len = #Value
	if len == 0 then
		return false
	end

	local count = 0
	for key, _ in Value do
		if typeof(key) ~= "number" or key < 1 or key > len or key % 1 ~= 0 then
			return false
		end
		count += 1
	end

	return count == len
end

const function IsNumberBetweenBounds(Value: number, Minimum: number, Maximum: number): boolean
	return Value >= Minimum and Value <= Maximum
end

const function GetTagFromValue(Value: any): number
	if Value == nil then
		return TAG_NIL
	end

	if Value == true then
		return TAG_TRUE
	end

	if Value == false then
		return TAG_FALSE
	end

	const Type = typeof(Value)

	if Type == "number" then
		--NaN and infinity
		--they shouldn't be sent as it's not supported and it's a bit unnecessary
		if Value ~= Value or Value == math.huge or Value == -math.huge then
			warn(`[Dysconnect] Value is NaN or +-Infinity! It'll be sent as nil!`)
			return TAG_NIL
		end

		if Value % 1 ~= 0 then --if the remainder of the number divided by 1 is 0 then there's no decimal remainder for the number therefore it's an int
			return if math.abs(Value) > 16_777_216 then TAG_FLOAT64 else TAG_FLOAT32 -- 2^24
		end

		if Value >= 0 then
			if IsNumberBetweenBounds(Value, 0, 255) then
				return TAG_UINT8
			end

			if IsNumberBetweenBounds(Value, 256, 65_535) then
				return TAG_UINT16
			end

			if IsNumberBetweenBounds(Value, 65_536, 4_294_967_295) then
				return TAG_UINT32
			end

			return TAG_FLOAT64
		end

		if Value >= -128 then -- signed:  -(2^8) / 2 ; (2^8) / 2 - 1
			return TAG_INT8
		end

		if Value >= -32_768 then -- signed:  -(2^16) / 2 ; (2^16) / 2 - 1
			return TAG_INT16
		end

		if Value >= -2_147_483_648 then -- signed:  -(2^32) / 2 ; (2^32) / 2 - 1
			return TAG_INT32
		end

		return TAG_FLOAT64
	end

	if Type == "table" then
		return IsArray(Value) and TAG_ARRAY or TAG_MAP
	end

	if Type == "string" then
		if #Value <= 255 then
			return TAG_STRING
		end

		if #Value <= 65_535 then
			return TAG_LONGSTRING
		end

		return TAG_LONGERSTRING
	end

	if Type == "CFrame" then
		const _, ang = (Value :: CFrame):ToAxisAngle()
		if math.abs(ang) < EPSILON then
			return TAG_CFRAMEPOS
		end

		return TAG_CFRAME
	end

	if ENUM[Type] then
		return ENUM[Type]
	end

	warn(`[Dysconnect] Item "{Value}" of type {Type} isn't supported by Dysconnect! Falling back to JSON...`)
	return TAG_JSON
end
BinaryCodec.GetTagFromValue = GetTagFromValue

const function GetPayloadSize(tag: number, value: any): number
	--if it has a fixed size, return that
	if FIXED_SIZES[tag] then
		return FIXED_SIZES[tag]
	end

	if tag == TAG_MAP then
		--yuh you kinda get the point
		--iterate through every item blah blah add their size to the total blah blah BORING.
		local total = 2
		for Key, Value in value do
			const KeyTag = GetTagFromValue(Key)
			const ValueTag = GetTagFromValue(Value)

			total += (1 + GetPayloadSize(KeyTag, Key))
			total += (1 + GetPayloadSize(ValueTag, Value))
		end
		return total
	end

	if tag == TAG_STRING then
		return 1 + #value
	elseif tag == TAG_LONGSTRING then
		return 2 + #value
	elseif tag == TAG_LONGERSTRING then
		return 3 + #value
	elseif tag == TAG_JSON then
		const encoded = HttpService:JSONEncode(value)
		return 4 + #encoded
	elseif tag == TAG_BUFFER then
		return 4 + buffer.len(value)
	elseif tag == TAG_COLORSEQUENCE then
		return 1 + (#value.Keypoints * 16)
	elseif tag == TAG_NUMBERSEQUENCE then
		return 1 + (#value.Keypoints * 12)
	elseif tag == TAG_ARRAY then
		local total = 2
		for _, Item in value do
			const ItemTag = GetTagFromValue(Item)
			total += 1 + GetPayloadSize(ItemTag, Item)
		end
		return total
	end

	return 0 --fallback even if it isn't possible to get here (fuck you selene!!!!!)
end
BinaryCodec.GetPayloadSize = GetPayloadSize

local WRITERS: { [number]: (Buffer: buffer, Count: number, Value: any, InstanceList: { Instance }) -> number }

const function GetWriter(Tag: number): (Buffer: buffer, Count: number, Value: any, InstanceList: { Instance }) -> number
	const Writer = WRITERS[Tag]
	if not Writer then
		error(`[Dysconnect] Writer not found for tag {Tag}!`)
	end
	return Writer
end
BinaryCodec.GetWriter = GetWriter

WRITERS = {
	[TAG_NIL] = function(_Buffer: buffer, Count: number): number
		return Count
	end,

	[TAG_FALSE] = function(_Buffer: buffer, Count: number): number
		return Count
	end,

	[TAG_TRUE] = function(_Buffer: buffer, Count: number): number
		return Count
	end,

	[TAG_INT8] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writei8(Buffer, Count, Value)
		return Count + 1
	end,

	[TAG_UINT8] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writeu8(Buffer, Count, Value)
		return Count + 1
	end,

	[TAG_INT16] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writei16(Buffer, Count, Value)
		return Count + 2
	end,

	[TAG_UINT16] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writeu16(Buffer, Count, Value)
		return Count + 2
	end,

	[TAG_INT32] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writei32(Buffer, Count, Value)
		return Count + 4
	end,

	[TAG_UINT32] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writeu32(Buffer, Count, Value)
		return Count + 4
	end,

	[TAG_FLOAT32] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writef32(Buffer, Count, Value)
		return Count + 4
	end,

	[TAG_FLOAT64] = function(Buffer: buffer, Count: number, Value: number): number
		buffer.writef64(Buffer, Count, Value)
		return Count + 8
	end,

	[TAG_VECTOR3] = function(Buffer: buffer, Count: number, Value: Vector3): number
		buffer.writef32(Buffer, Count, Value.X)
		buffer.writef32(Buffer, Count + 4, Value.Y)
		buffer.writef32(Buffer, Count + 8, Value.Z)
		return Count + 12
	end,

	[TAG_JSON] = function(Buffer: buffer, Count: number, Value: any): number
		const encoded = HttpService:JSONEncode(Value)
		const len = #encoded
		buffer.writeu32(Buffer, Count, len)
		buffer.writestring(Buffer, Count + 4, encoded)
		return Count + 4 + len
	end,

	[TAG_BUFFER] = function(Buffer: buffer, Count: number, Value: buffer): number
		const len = buffer.len(Value)
		buffer.writeu32(Buffer, Count, len)
		buffer.copy(Buffer, Count + 4, Value, 0, len)
		return Count + 4 + len
	end,

	[TAG_STRING] = function(Buffer: buffer, Count: number, Value: string): number
		const len = #Value
		if len > 65535 then
			warn(`[Dysconnect] String "{Value} exceeds 255 character limit for string!"`)
			buffer.writeu8(Buffer, Count, 0)
			return Count + 1
		end
		buffer.writeu8(Buffer, Count, len)
		buffer.writestring(Buffer, Count + 1, Value)
		return Count + 1 + len
	end,

	[TAG_LONGSTRING] = function(Buffer: buffer, Count: number, Value: string): number
		const len = #Value
		if len > 65535 then
			warn(`[Dysconnect] String "{Value} exceeds 65535 character limit for LongString!"`)
			buffer.writeu16(Buffer, Count, 0)
			return Count + 2
		end
		buffer.writeu16(Buffer, Count, len)
		buffer.writestring(Buffer, Count + 2, Value)
		return Count + 2 + len
	end,

	[TAG_LONGERSTRING] = function(Buffer: buffer, Count: number, Value: string): number
		const len = #Value
		if len > 4_294_967_295 then
			warn(`[Dysconnect] String "{Value} exceeds 65535 character limit for LongString!"`)
			buffer.writeu32(Buffer, Count, 0)
			return Count + 3
		end
		buffer.writeu32(Buffer, Count, len)
		buffer.writestring(Buffer, Count + 3, Value)
		return Count + 3 + len
	end,
	
	[TAG_CFRAMEPOS] = function(Buffer: buffer, Count: number, Value: CFrame): number
		const pos = Value.Position
		buffer.writef32(Buffer, Count, pos.X)
		buffer.writef32(Buffer, Count + 4, pos.Y)
		buffer.writef32(Buffer, Count + 8, pos.Z)
		return Count + 12
	end,

	[TAG_CFRAME] = function(Buffer: buffer, Count: number, Value: CFrame): number
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

	[TAG_VECTOR2] = function(Buffer: buffer, Count: number, Value: Vector2): number
		buffer.writef32(Buffer, Count, Value.X)
		buffer.writef32(Buffer, Count + 4, Value.Y)
		return Count + 8
	end,

	[TAG_COLOR3] = function(Buffer: buffer, Count: number, Value: Color3): number
		buffer.writef32(Buffer, Count, Value.R)
		buffer.writef32(Buffer, Count + 4, Value.G)
		buffer.writef32(Buffer, Count + 8, Value.B)
		return Count + 12
	end,

	[TAG_UDIM2] = function(Buffer: buffer, Count: number, Value: UDim2): number
		buffer.writef32(Buffer, Count, Value.X.Scale)
		buffer.writei32(Buffer, Count + 4, Value.X.Offset)
		buffer.writef32(Buffer, Count + 8, Value.Y.Scale)
		buffer.writei32(Buffer, Count + 12, Value.Y.Offset)
		return Count + 16
	end,

	[TAG_BRICKCOLOR] = function(Buffer: buffer, Count: number, Value: BrickColor): number
		buffer.writeu16(Buffer, Count, Value.Number)
		return Count + 2
	end,

	[TAG_RECT] = function(Buffer: buffer, Count: number, Value: Rect): number
		buffer.writef32(Buffer, Count, Value.Min.X)
		buffer.writef32(Buffer, Count + 4, Value.Min.Y)
		buffer.writef32(Buffer, Count + 8, Value.Max.X)
		buffer.writef32(Buffer, Count + 12, Value.Max.Y)
		return Count + 16
	end,

	[TAG_NUMBERRANGE] = function(Buffer: buffer, Count: number, Value: NumberRange): number
		buffer.writef32(Buffer, Count, Value.Min)
		buffer.writef32(Buffer, Count + 4, Value.Max)
		return Count + 8
	end,

	[TAG_UDIM] = function(Buffer: buffer, Count: number, Value: UDim): number
		buffer.writef32(Buffer, Count, Value.Scale)
		buffer.writei32(Buffer, Count + 4, Value.Offset)
		return Count + 8
	end,

	[TAG_DATETIME] = function(Buffer: buffer, Count: number, Value: DateTime): number
		buffer.writeu32(Buffer, Count, Value.UnixTimestamp)
		return Count + 4
	end,

	[TAG_COLORSEQUENCE] = function(Buffer: buffer, Count: number, Value: ColorSequence): number
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

	[TAG_NUMBERSEQUENCE] = function(Buffer: buffer, Count: number, Value: NumberSequence): number
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

	[TAG_TWEENINFO] = function(Buffer: buffer, Count: number, Value: TweenInfo): number
		buffer.writef32(Buffer, Count, Value.Time)
		buffer.writeu8(Buffer, Count + 4, Value.EasingStyle.Value)
		buffer.writeu8(Buffer, Count + 5, Value.EasingDirection.Value)
		buffer.writei32(Buffer, Count + 6, Value.RepeatCount)
		buffer.writeu8(Buffer, Count + 10, Value.Reverses and 1 or 0)
		buffer.writef32(Buffer, Count + 11, Value.DelayTime)

		return Count + 15
	end,

	[TAG_INSTANCE] = function(Buffer: buffer, Count: number, Value: Instance, InstanceList: { Instance }): number
		const Length = #InstanceList
		if Length >= 65_535 then
			warn(`[Dysconnect] Instance count exceeds the cap of 65535 elements! {Value} will be sent as nil!`)
			return Count
		end
		table.insert(InstanceList, Value)

		buffer.writeu16(Buffer, Count, Length + 1)
		return Count + 2
	end,

	[TAG_MAP] = function(Buffer: buffer, Count: number, Value: { any }, InstanceList: { Instance }): number
		--not using utils here just in case i wanna reuse this for a different game
		local TableCount = 0
		for _, _ in Value do
			TableCount += 1
		end

		if TableCount > 65535 then
			error(`[Dysconnect] Can't send a table with {TableCount} entries! Aborting buffering... (max is 65535)`)
		end

		buffer.writeu16(Buffer, Count, TableCount) --write le count
		Count += 2

		for key, val in Value do
			const KeyTag = GetTagFromValue(key)
			const ValueTag = GetTagFromValue(val)

			--write le key
			buffer.writeu8(Buffer, Count, KeyTag)
			Count += 1
			const KeyWriter = GetWriter(KeyTag)
			if not KeyWriter then
				Count += 1 --skip the value
				continue
			end
			Count = KeyWriter(Buffer, Count, key, InstanceList)

			--write le value after le key
			buffer.writeu8(Buffer, Count, ValueTag)
			Count += 1
			const ValueWriter = GetWriter(ValueTag)
			if not ValueWriter then
				Count += 1 --skip the value
				continue
			end
			Count = ValueWriter(Buffer, Count, val, InstanceList)
		end

		return Count
	end,

	[TAG_VECTOR2INT16] = function(Buffer: buffer, Count: number, Value: Vector2int16): number
		buffer.writei16(Buffer, Count, Value.X)
		buffer.writei16(Buffer, Count + 2, Value.Y)
		return Count + 4
	end,

	[TAG_VECTOR3INT16] = function(Buffer: buffer, Count: number, Value: Vector3int16): number
		buffer.writei16(Buffer, Count, Value.X)
		buffer.writei16(Buffer, Count + 2, Value.Y)
		buffer.writei16(Buffer, Count + 4, Value.Z)
		return Count + 6
	end,

	[TAG_ARRAY] = function(Buffer: buffer, Count: number, Value: { any }, InstanceList: { Instance }): number
		const len = #Value
		if len > 65535 then
			error(`[Dysconnect] Can't send a table with {len} entries! Aborting buffering... (max is 65535)`)
		end

		buffer.writeu16(Buffer, Count, len)
		Count += 2

		for Index = 1, len do
			const Item = Value[Index]
			const ItemTag = GetTagFromValue(Item)
			buffer.writeu8(Buffer, Count, ItemTag)
			Count += 1
			const Writer = GetWriter(ItemTag)
			if not Writer then
				continue
			end
			Count = Writer(Buffer, Count, Item, InstanceList)
		end

		return Count
	end,
}

local READERS: { (Buffer: buffer, Count: number, InstanceList: { Instance }, ...any) -> (any, number) }

const function GetReader(Tag: number): (Buffer: buffer, Count: number, InstanceList: { Instance }, ...any) -> (any, number)
	const Reader = READERS[Tag]
	if not Reader then
		error(`[Dysconnect] Reader not found for tag {Tag}!`)
	end
	return Reader
end
BinaryCodec.GetReader = GetReader

READERS = {
	[TAG_NIL] = function(_Buffer: buffer, Count: number): (nil, number)
		return nil, Count
	end,

	[TAG_FALSE] = function(_Buffer: buffer, Count: number): (false, number)
		return false, Count
	end,

	[TAG_TRUE] = function(_Buffer: buffer, Count: number): (true, number)
		return true, Count
	end,

	[TAG_INT8] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readi8(Buffer, Count), Count + 1
	end,

	[TAG_UINT8] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readu8(Buffer, Count), Count + 1
	end,

	[TAG_INT16] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readi16(Buffer, Count), Count + 2
	end,

	[TAG_UINT16] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readu16(Buffer, Count), Count + 2
	end,

	[TAG_INT32] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readi32(Buffer, Count), Count + 4
	end,

	[TAG_UINT32] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readu32(Buffer, Count), Count + 4
	end,

	[TAG_FLOAT32] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readf32(Buffer, Count), Count + 4
	end,

	[TAG_FLOAT64] = function(Buffer: buffer, Count: number): (number, number)
		return buffer.readf64(Buffer, Count), Count + 8
	end,

	[TAG_VECTOR3] = function(Buffer: buffer, Count: number): (Vector3, number)
		return Vector3.new(buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4), buffer.readf32(Buffer, Count + 8)), Count + 12
	end,

	[TAG_JSON] = function(Buffer: buffer, Count: number): (any, number)
		const len = buffer.readu32(Buffer, Count)
		const content = buffer.readstring(Buffer, Count + 4, len)
		return HttpService:JSONDecode(content), Count + 4 + len
	end,

	[TAG_BUFFER] = function(Buffer: buffer, Count: number): (buffer, number)
		const len = buffer.readu32(Buffer, Count)
		if len > buffer.len(Buffer) - (Count + 4) then
			error("[Dysconnect] Malformed buffer length.")
		end
		const newBuf = buffer.create(len)
		buffer.copy(newBuf, 0, Buffer, Count + 4, len)
		return newBuf, Count + 4 + len
	end,

	[TAG_STRING] = function(Buffer: buffer, Count: number): (string, number)
		const len = buffer.readu8(Buffer, Count)
		return buffer.readstring(Buffer, Count + 1, len), Count + 1 + len
	end,

	[TAG_LONGSTRING] = function(Buffer: buffer, Count: number): (string, number)
		const len = buffer.readu16(Buffer, Count)
		return buffer.readstring(Buffer, Count + 2, len), Count + 2 + len
	end,

	[TAG_LONGERSTRING] = function(Buffer: buffer, Count: number): (string, number)
		const len = buffer.readu32(Buffer, Count)
		return buffer.readstring(Buffer, Count + 3, len), Count + 3 + len
	end,

	[TAG_CFRAMEPOS] = function(Buffer: buffer, Count: number): (CFrame, number)
		return CFrame.new(buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4), buffer.readf32(Buffer, Count + 8)), Count + 12
	end,

	[TAG_CFRAME] = function(Buffer: buffer, Count: number): (CFrame, number)
		const pos = Vector3.new(buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4), buffer.readf32(Buffer, Count + 8))
		const axis = Vector3.new(buffer.readf32(Buffer, Count + 12), buffer.readf32(Buffer, Count + 16), buffer.readf32(Buffer, Count + 20))
		const ang = buffer.readf32(Buffer, Count + 24)
		return CFrame.new(pos) * CFrame.fromAxisAngle(axis, ang), Count + 28
	end,

	[TAG_VECTOR2] = function(Buffer: buffer, Count: number): (Vector2, number)
		return Vector2.new(buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4)), Count + 8
	end,

	[TAG_COLOR3] = function(Buffer: buffer, Count: number): (Color3, number)
		return Color3.new(buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4), buffer.readf32(Buffer, Count + 8)), Count + 12
	end,

	[TAG_UDIM2] = function(Buffer: buffer, Count: number): (UDim2, number)
		return UDim2.new(buffer.readf32(Buffer, Count), buffer.readi32(Buffer, Count + 4), buffer.readf32(Buffer, Count + 8), buffer.readi32(Buffer, Count + 12)), Count + 16
	end,

	[TAG_BRICKCOLOR] = function(Buffer: buffer, Count: number): (BrickColor, number)
		return BrickColor.new(buffer.readu16(Buffer, Count)), Count + 2
	end,

	[TAG_RECT] = function(Buffer: buffer, Count: number): (Rect, number)
		return Rect.new(buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4), buffer.readf32(Buffer, Count + 8), buffer.readf32(Buffer, Count + 12)), Count + 16
	end,

	[TAG_NUMBERRANGE] = function(Buffer: buffer, Count: number): (NumberRange, number)
		return NumberRange.new(buffer.readf32(Buffer, Count), buffer.readf32(Buffer, Count + 4)), Count + 8
	end,

	[TAG_UDIM] = function(Buffer: buffer, Count: number): (UDim, number)
		return UDim.new(buffer.readf32(Buffer, Count), buffer.readi32(Buffer, Count + 4)), Count + 8
	end,

	[TAG_DATETIME] = function(Buffer: buffer, Count: number): (DateTime, number)
		return DateTime.fromUnixTimestamp(buffer.readu32(Buffer, Count)), Count + 4
	end,

	[TAG_COLORSEQUENCE] = function(Buffer: buffer, Count: number): (ColorSequence, number)
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

	[TAG_NUMBERSEQUENCE] = function(Buffer: buffer, Count: number): (NumberSequence, number)
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

	[TAG_TWEENINFO] = function(Buffer: buffer, Count: number): (TweenInfo, number)
		const Time = buffer.readf32(Buffer, Count)
		const StyleId = buffer.readu8(Buffer, Count + 4)
		const DirectionId = buffer.readu8(Buffer, Count + 5)
		const count = buffer.readi32(Buffer, Count + 6)
		const reverses = buffer.readu8(Buffer, Count + 10) == 1
		const Delay = buffer.readf32(Buffer, Count + 11)

		const style = StyleMap[StyleId] or Enum.EasingStyle.Linear
		const dir = DirectionMap[DirectionId] or Enum.EasingDirection.Out

		return TweenInfo.new(Time, style, dir, count, reverses, Delay), Count + 15
	end,

	[TAG_INSTANCE] = function(Buffer: buffer, Count: number, InstanceList: { Instance }): (Instance?, number)
		const index = buffer.readu16(Buffer, Count)
		const inst = InstanceList and InstanceList[index] or nil
		return inst, Count + 2
	end,

	[TAG_MAP] = function(Buffer: buffer, Count: number, InstanceList: { Instance }): ({ any }, number)
		const count = buffer.readu16(Buffer, Count)
		Count += 2

		const Table = {}
		for _ = 1, count do
			--read le key
			const KeyTag = buffer.readu8(Buffer, Count)
			Count += 1
			const KeyReader = GetReader(KeyTag)
			if not KeyReader then
				Count += 1 --skip the value
				continue
			end
			local Key
			Key, Count = KeyReader(Buffer, Count, InstanceList)

			if Key == nil then
				warn(`[Dysconnect] Nil map key, skipping.`)
				continue
			end
			if Key ~= Key then --this might look stupid BUT it works
				warn(`[Dysconnect] NaN map key, skipping.`)
				continue
			end

			--read le value
			const ValueTag = buffer.readu8(Buffer, Count :: any)
			Count += 1
			const ValueReader = GetReader(ValueTag)
			if not ValueReader then
				continue
			end
			local Value
			Value, Count = ValueReader(Buffer, Count, InstanceList)

			--set the damn thing
			Table[Key] = Value
		end

		return Table, Count
	end,

	[TAG_VECTOR2INT16] = function(Buffer: buffer, Count: number): (Vector2int16, number)
		return Vector2int16.new(buffer.readi16(Buffer, Count), buffer.readi16(Buffer, Count + 2)), Count + 4
	end,

	[TAG_VECTOR3INT16] = function(Buffer: buffer, Count: number): (Vector3int16, number)
		return Vector3int16.new(buffer.readi16(Buffer, Count), buffer.readi16(Buffer, Count + 2), buffer.readi16(Buffer, Count + 4)), Count + 6
	end,

	[TAG_ARRAY] = function(Buffer: buffer, Count: number, InstanceList: { Instance }, Depth: number): ({ any }, number)
		const len = buffer.readu16(Buffer, Count)
		Count += 2

		if Depth ~= nil then
			if Depth > 32 then
				error(`[Dysconnect] Max nesting depth exceeded!`)
			end
			Depth += 1
		else
			Depth = 1
		end

		const Result = table.create(len)
		for Index = 1, len do
			const ItemTag = buffer.readu8(Buffer, Count)
			Count += 1
			const Reader = GetReader(ItemTag)
			if not Reader then
				continue
			end
			local Item
			Item, Count = Reader(Buffer, Count, InstanceList, Depth)
			Result[Index] = Item
		end

		return Result, Count
	end,
}

return DeepFreezeTable(BinaryCodec)
