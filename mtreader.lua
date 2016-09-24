--[[
Read MONOTONE file and prints out as readable form.
]]

local args = {...}

-- @return string: array of bytes
function fetchAsBytes()
	local path = args[1]
	local file = io.open(path, "rb")
	
	-- sets the default input
	io.input(file)
	
	local bytes = io.read("*all")
	
	file.close()

	return bytes
end

function printArray(t, length)
	for c, i in ipairs(t) do
		if (c > length) then break end
		io.write(string.format("%02X", i).." ")
	end
	io.write("\n")
end

-- @return string note (e.g. "A#3")
function toNote(raw)	
	-- extract note index from LSB
	local note = bit32.rshift(raw, 9)

	if note == 0 then return "..." end
	if note == 0x7F then return "===" end -- off
	-- A-0 is index 1
	local noteslist = {"A-", "A#", "B-", "C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#"}
	local octave = math.floor((note + 8) / 12)
	if (octave == 10) then octave = "A" end -- a note this high is not allowed in MONOTONE editor, though

	if (note % 12 == 0) then
		return (noteslist[12]..octave)
	else
		return (noteslist[(note) % 12]..octave)
	end
end

-- @return effect, arg1[, arg2]
function toEffect(raw)
	raw = bit32.band(raw, 0x1FF)

	if (raw == 0) then return "..." end

	local effectslist = {"0", "1", "2", "3", "4", "B", "D", "F"}
	function isTwoArgEff(raw) return bit32.rshift(raw, 6) == 0 or bit32.rshift(raw, 6) == 4 end

	function getEffIndex(raw) return bit32.rshift(raw, 6) + 1 end
	function getArgXX(raw) return bit32.band(raw, 0x3F) end
	function getArgXY(raw) return bit32.rshift(bit32.band(raw, 0x38), 3), bit32.band(raw, 7) end
	function getArg(raw) if (isTwoArgEff(raw)) then return getArgXY(raw) else return getArgXX(raw) end end

	effname = effectslist[getEffIndex(raw)]
	effargs1, effargs2 = getArg(raw)

	if not effargs2 then
		return string.format("%s%02X", effname, effargs1)
	else
		return string.format("%s%X%X", effname, effargs1, effargs2)
	end
end

function noteToString(raw)
	return toNote(raw).." "..toEffect(raw)
end

-- @return string as byte array (a part of the input file)
function fetchOrder(file, ordr)
	local voices = file:byte(0x5D + 1)
	local patternsize = 0x40 * 2 * voices
	local offsetfile = 0x15F + 1
	local offset = patternsize * ordr + offsetfile
	local ret = file:sub(offset, offset + patternsize - 1)

	if (#ret ~= patternsize) then error("Coding error: fetched pattern size does not match: (expected "..patternsize..", got "..#ret..")") end

	return ret
end

function printOrdr(file, ordr)
	local COLSEP = " | "
	local voices = file:byte(0x5D + 1)
	local pattern = fetchOrder(file, ordr)

	print("Order "..string.format("%02X", ordr))
	io.write("rw"..COLSEP.."nnn edd")
	for i=2,voices do io.write(COLSEP.."nnn edd") end print("\n")

	for i=1, 0x40 * voices * 2, 2 do
		if ((i - 1) / 2) % voices == 0 and i > 3 then print() end

		local msb = pattern:byte(i)
		local lsb = pattern:byte(i + 1)

		local word = lsb*256 + msb

		if ((i - 1) / 2) % voices == 0 then
			io.write(string.format("%02X", (i - 1) / (2 * voices))..COLSEP..noteToString(word))
		else
			io.write(COLSEP..noteToString(word))
		end
	end

	print("\n")
end

--MAIN-------------------------------------------------------------------------


local magic = "\x08\x4D\x4F\x4E\x4F\x54\x4F\x4E\x45\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01"


local file = fetchAsBytes()

-- check magic
if file:sub(1,0x5C) ~= magic then
	print("Invalid MONOTONE file!")
end

-- magic passed, start parsing
print("File", args[1])

local songlen = file:byte(0x5C + 1) -- index starts from 1 !
local voices = file:byte(0x5D + 1)
local orderlistRaw = file:sub(0x5F + 1, 0x15E + 1)
local orderlist = {} -- array of int

-- parse orderlist
for i = 1, #orderlistRaw do
	local p = orderlistRaw:byte(i)
	if (p < 0xFF) then -- ignore pattern no. 0xFF
		table.insert(orderlist, orderlistRaw:byte(i))
	end
end

print("Length", songlen.." patterns")
print("voices", voices)
print("Order list:")
printArray(orderlist, songlen + 1)
print()


for i, k in ipairs(orderlist) do
	if (i > songlen + 1) then break end
	printOrdr(file, k)
end



::terminate::
return 0
