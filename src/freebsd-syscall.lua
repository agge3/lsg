--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2023 Warner Losh <imp@bsdimp.com>
-- Copyright (c) 2024 Tyler Baxter <agge@FreeBSD.org>
--

-- Derived in large part from makesyscalls.lua:
--
-- SPDX-License-Identifier: BSD-2-Clause-FreeBSD
--
-- Copyright (c) 2019 Kyle Evans <kevans@FreeBSD.org>

local syscall = require("syscall")

local FreeBSDSyscall = {}

FreeBSDSyscall.__index = FreeBSDSyscall

-- xxx probably a better place for this
local function validate()
end

-- xxx this will likely need to go here
function FreeBSDSyscall:processCompat()
    -- xxx haven't reworked yet
	--local nval = 0
	--for _, v in pairs(known_flags) do
	--	if v > nval then
	--		nval = v
	--	end
	--end

	--nval = nval << 1
	--for _, v in pairs(compat_options) do
	--	if v.stdcompat ~= nil then
	--		local stdcompat = v.stdcompat
	--		v.definition = "COMPAT_" .. stdcompat:upper()
	--		v.compatlevel = tonumber(stdcompat:match("([0-9]+)$"))
	--		v.flag = stdcompat:gsub("FREEBSD", "COMPAT")
	--		v.prefix = stdcompat:lower() .. "_"
	--		v.descr = stdcompat:lower()
	--	end

	--	local tmpname = "sys" .. v.flag:lower()
	--	local dcltmpname = tmpname .. "dcl"
	--	files[tmpname] = io.tmpfile()
	--	files[dcltmpname] = io.tmpfile()
	--	v.tmp = tmpname
	--	v.dcltmp = dcltmpname

	--	known_flags[v.flag] = nval
	--	v.mask = nval
	--	nval = nval << 1

	--	v.count = 0
	--end
end

function FreeBSDSyscall:parse_sysfile()
	local file = self.sysfile
	local config = self.config
	local commentExpr = "^%s*;.*"

	if file == nil then
		print "No file"
		return
	end

	self.syscalls = { }

	local fh = io.open(file)
	if fh == nil then
		print("Failed to open " .. file)
		return {}
	end

	local incs = ""
	local defs = ""
	local s
	for line in fh:lines() do
		line = line:gsub(commentExpr, "")		-- Strip any comments

		-- Note can't use pure pattern matching here because of the 's' test
		-- and this is shorter than a generic pattern matching pattern
		if line == nil or line == "" then
			-- nothing blank line or end of file
		elseif s ~= nil then
			-- If we have a partial system call object
			-- s, then feed it one more line
			if s:add(line) then
				-- append to syscall list
				for t in s:iter() do
					table.insert(self.syscalls, t)
				end
				s = nil
			end
		elseif line:match("^%s*%$") then
			-- nothing, obsolete $FreeBSD$ thing
		elseif line:match("^#%s*include") then
			incs = incs .. line .. "\n"
		elseif line:match("%%ABI_HEADERS%%") then
			local h = self.config.abi_headers
			if h ~= nil and h ~= "" then
				incs = incs .. h .. "\n"
			end
		elseif line:match("^#%s*define") then
			defs = defs .. line.. "\n"
		elseif line:match("^#") then
			util.abort(1, "Unsupported cpp op " .. line)
		else
			s = syscall:new()
			if s:add(line) then
				-- append to syscall list
				for t in s:iter() do
					table.insert(self.syscalls, t)
				end
				s = nil
            end
		end
	end

    -- special handling for linux nosys
    if config.syscallprefix:find("LINUX") ~= nil then
        -- xxx do more here? want to discuss, looks like we're currently 
        -- skipping?
        s = nil
    end

	if s ~= nil then
		util.abort(1, "Dangling system call at the end")
	end

	assert(io.close(fh))
	self.includes = incs
	self.defines = defs
end

function FreeBSDSyscall:new(obj)
	obj = obj or { }
	setmetatable(obj, self)
	self.__index = self

	obj:parse_sysfile()

	return obj
end

return FreeBSDSyscall
