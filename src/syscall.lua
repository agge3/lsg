--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2023 Warner Losh <imp@bsdimp.com>
-- Copyright (c) 2024 Tyler Baxter <agge@FreeBSD.org>
--

local util = require("util")
local scarg = require("scarg")
local scret = require("scret")

local syscall = {}

syscall.__index = syscall

syscall.known_flags = util.set {
	"STD",
	"OBSOL",
	"RESERVED",
	"UNIMPL",
	"NODEF",
	"NOARGS",
	"NOPROTO",
	"NOSTD",
	"NOTSTATIC",
	"CAPENABLED",
	"SYSMUX",
}

--
-- Processes the thread flag for the system call.
-- RETURN: String thr, the appropriate thread flag
--
local function processThr(type)
    local str = "SY_THR_STATIC"
    for k, v in pairs(type) do
        if k == "NOTSTATIC" then
            str = "SY_THR_ABSENT"
        end
    end
    return str
end

--
-- Processes the capability flag for the system call.
-- RETURN: String cap, "SYF_CAPENABLED" for capability enabled, "0" if not
--
local function processCap(name, prefix, type)
    local str = "0"
    local stripped = util.stripAbiPrefix(name, prefix)
    if config.capenabled[name] ~= nil or
       config.capenabled[stripped] ~= nil then
        str = "SYF_CAPENABLED"
    else
        for k, v in pairs(type) do
            if k == "CAPENABLED" then
                str = "SYF_CAPENABLED"
            end
        end
    end
    return str
end

-- Validates a system call's type, aborts if unknown.
local function checkType(line, type)
	for k, v in pairs(type) do
	    if not syscall.known_flags[k] and not
            k:match("^COMPAT") then
			util.abort(1, "Bad type: " .. k)
		end
	end
end

function syscall:validate(prev)
    return prev + 1 == self.num
end

-- If there are ABI changes from native, process the system call to match the
-- expected ABI.
function syscall:processAbiChanges()
    if config.changes_abi and self.name ~= nil then
        -- argalias should be:
        --   COMPAT_PREFIX + ABI Prefix + funcname
    	self.arg_prefix = config.abi_func_prefix
    	self.prefix = config.abi_func_prefix
    	self.arg_alias = self.prefix .. self.name
    	return true
    end
    return false
end

-- Native is an arbitrarily large number to have a constant and not 
-- interfere with compat numbers.
local native = 1000000

-- Return the symbol name for this system call.
function syscall:symbol()
	local c = self:compat_level()
	if self.type.OBSOL then
		return "obs_" .. self.name
	end
	if self.type.RESERVED then
		return "reserved #" .. tostring(self.num)
	end
	if self.type.UNIMPL then
		return "unimp_" .. self.name
	end
	if c == 3 then
		return "o" .. self.name
	end
	if c < native then
		return "freebsd" .. tostring(c) .. "_" .. self.name
	end
	return self.name
end

-- Return the comment for this system call.
function syscall:comment()
    local c = self:compat_level()
    if self.type.OBSOL then
        return "/* obsolete " .. self.alias .. " */"
    end
    if self.type.RESERVED then
        return "/* reserved for local use */"
    end
    if self.type.UNIMPL then
        return "" -- xxx not seeing where there is
    else
        return "/* " .. self.num .. " = " .. self.alias .. " */"
    end
end

--
-- Return the compatibility level for this system call.
-- 0 is obsolete
-- < 0 is this isn't really a system call we care about
-- 3 is 4.3BSD in theory, but anything before FreeBSD 4
-- >= 4 FreeBSD version this system call was replaced with a new version
--
function syscall:compat_level()
	if self.type.UNIMPL or self.type.RESERVED or self.type.NODEF then
		return -1
	elseif self.type.OBSOL then
		return 0
	elseif self.type.COMPAT then
		return 3
	end
	for k, v in pairs(self.type) do
		local l = k:match("^COMPAT(%d+)")
		if l ~= nil then
			return tonumber(l)
		end
	end
	return native
end
    
--
-- Adds the definition for the system call.
-- NOTE: Is guarded by the system call number ~= nil
-- RETURN: TRUE, if the definition was added. FALSE, if not
--
function syscall:addDef(line, words)
    if self.num == nil then
	    self.num = words[1]

        --if tonumber(self.num) == nil then -- handle range of system calls
        --    self.range = true
        --end

	    self.audit = words[2]
	    self.type = util.setFromString(words[3], "[^|]+")
	    checkType(line, self.type)
	    self.name = words[4]
	    -- These next three are optional, and either all present or all absent
	    self.altname = words[5]
	    self.alttag = words[6]
	    self.alttype = words[7]
	    return true
    end
    return false
end

-- 
-- Adds the function declaration for the system call.
-- NOTE: Is guarded by validation of the definition.
-- RETURN: TRUE, if the function declaration was added. FALSE, if not
--
function syscall:addFunc(line, words)
    if self.name == "{" then
	    -- Expect line is "type syscall(" or "type syscall(void);"
        if #words ~= 2 then
            util.abort(1, "Malformed line " .. line)
        end

	    local ret = scret:new({ }, words[1])
        self.rettype = ret:add()
    
	    self.name = words[2]:match("([%w_]+)%(")
	    if words[2]:match("%);$") then
            -- now we're looking for ending curly brace
	    	self.expect_rbrace = true
	    end
        return true
    end
    return false
end

--
-- Adds the argument(s) for the system call.
-- NOTE: Is guarded by validation of the function declaration.
-- RETURN: TRUE, if the argument(s) were added. FALSE, if not
--
function syscall:addArgs(line)
	if not self.expect_rbrace then
	    if line:match("%);$") then
	    	self.expect_rbrace = true
	    	return true
	    end

        -- scarg is going to instantiate itself with its own methods
	    local arg = scarg:new({ }, line)
        -- if arg processes, then add. if not, don't add
        if arg:process() then 
            arg:append(self.args)
        end
        arg = nil -- nil the reference to trigger scarg's finalizer
        return true
    end
    return false
end

--
-- Confirm that the system call was added succesfully, ABORT if not.
-- RETURN: TRUE, if added succesfully. FALSE (or ABORT), if not
--
function syscall:isAdded(line)
    --
    -- Three cases:
    --  (1) This system call was a range of system calls - exit with specific 
    --  procedures.
    --  (2) This system call was a loadable system call - exit with specific 
    --  procedures.
    --  (3) (Common case) This system call was a full system call - confirm 
    --  there's a closing curly brace and perform standard finalize procedure.
    -- 
    --if self.range or self.name ~="{" then
    --    self.alias = self.name
    --    return true
    --end
    --if self.altname ~= nil and self.alttag ~= nil and 
    --       self.alttype ~= nil then
    --    self.alias = self.name
    --    self.cap = "0"
    --    self.thr = "SY_THR_ABSENT"
    --    return true
    --end
    --if self.name ~= "{" then
    --    self.alias = self.name
    --    if tonumber(self.num) == nil then
    --        --print("range caught at " .. self.num)
    --        return true
    --    elseif self.altname ~= nil then
    --        --print("loadable system call caught at " .. self.num)
    --        self.cap = "0"
    --        self.thr = "SY_THR_ABSENT"
    --        self.arg_alias = self:symbol() .. "_args"
    --        --self.audit = "ERROR AT LKMNOSYS"
    --        return true
    --    else
    --        --print("incomplete definition caught at " .. self.num)
    --        return true
    --    end
    --end
    if self.expect_rbrace then
	    if not line:match("}$") then
	    	util.abort(1, "Expected '}' found '" .. line .. "' instead.")
	    end
        self:finalize()
        return true
    end
    return false
end

-- Once we have a good syscall, add some final information to it (based on how 
-- it was instantiated).
function syscall:finalize()
    -- These may be changed by processAbiChanges(), or they'll remain empty for 
    -- native.
    self.prefix = ""
    self.arg_prefix = ""

    -- capability flag, if it was provided
    self.cap = processCap(self.name, self.prefix, self.type)
    -- thread flag, based on type(s) provided
    self.thr = processThr(self.type)

    self:processAbiChanges()

    if self.name ~= nil then
        self.name = self.prefix .. self.name
    end
    if self.alias == nil or self.alias == "" then
        self.alias = self.name
    end

    -- Handle argument(s) alias.
    if self.arg_alias == nil and self.name ~= nil then
        -- Symbol will either be: (native) the same as the system call name, or 
        -- (non-native) the correct modified symbol for the arg_alias
        self.arg_alias = self:symbol() .. "_args"
    elseif self.arg_alias ~= nil then 
        self.arg_alias = self.arg_prefix .. self.arg_alias
    end
end

--
-- Interface to add a system call. To be added to the master system call object,
-- FreeBSDSyscall.
--
-- NOTE: The system call is built up one line at a time, validating through four 
-- states, before confirmed to be added.
--
-- RETURN: TRUE, if system call processing is successful (and ready to add)
--         FALSE, if still processing
--         ABORT, with error
--
function syscall:add(line)
    local words = util.split(line, "%S+")
    if self:addDef(line, words) then
        -- Cases where we just want to exit and add - nothing else to do.
        if self.name ~= "{" then
            self.alias = self.name -- set for all these cases
            -- This system call was a range.
            if tonumber(self.num) == nil then
                return true
            -- This system call is a loadable system call.
            elseif self.altname ~= nil and self.alttag ~= nil and 
                   self.alttype ~= nil then
                self.cap = "0"
                self.thr = "SY_THR_ABSENT"
                self.arg_alias = self:symbol() .. "_args"
                return true
            -- This system call does not have a full instantiation.
            else
                return true
            end
        end
        return false -- otherwise, definition added - keep going
    end
    if self:addFunc(line, words) then
        return false -- function added, keep going
    end
    if self:addArgs(line) then
        return false -- arguments added, keep going
    end
    return self:isAdded(line) -- final validation, before adding
end

--
-- Return TRUE if this system call is native, FALSE if not
--
-- NOTE: The other system call names are also treated as native, so that's why
-- they're being allowed in here.
--
function syscall:native()
    return self:compat_level() == native or self.name == "lkmnosys" or 
           self.name == "sysarch"
end

function syscall:new(obj)
	obj = obj or { }
	setmetatable(obj, self)
	self.__index = self

    self.range = false

	self.expect_rbrace = false
	self.args = { }

	return obj
end

--
-- Make a shallow copy of `self` and replace the system call number with num 
-- (which should be a number).
-- USAGE: For system call ranges.
--
function syscall:shallowCopy(num)
	local obj = syscall:new(obj)

	-- shallow copy
	for k, v in pairs(self) do
		obj[k] = v
	end
	obj.num = num	-- except override range
	return obj
end

--
-- Make a deep copy of the parameter object.
-- USAGE: For a full system call (i.e., nested arguments table).
-- CREDIT: http://lua-users.org/wiki/CopyTable
--
local function deepCopy(orig)
    local type = type(orig)
    local copy

    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepCopy(orig_key)] = deepCopy(orig_value)
        end
        setmetatable(copy, deepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end

    return copy
end

-- CREDIT: http://lua-users.org/wiki/CopyTable
-- Save copied tables in `copies`, indexed by original table.
function deepCopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for orig_key, orig_value in next, orig, nil do
                copy[deepCopy(orig_key, copies)] = deepCopy(orig_value, copies)
            end
            setmetatable(copy, deepCopy(getmetatable(orig), copies))
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

--
-- As we're parsing the system calls, there's two types. Either we have a
-- specific one, that's a assigned a number, or we have a range for things like
-- reseved system calls. this function deals with both knowing that the specific
-- ones are more copy and so we should just return the object we just made w/o
-- an extra clone.
--
function syscall:iter()
	local s = tonumber(self.num)
	local e
	if s == nil then
		s, e = string.match(self.num, "(%d+)%-(%d+)")
        s, e = tonumber(s), tonumber(e)
		return function ()
			if s <= e then
				s = s + 1
				return self:shallowCopy(s - 1)
			end
		end
	else
		e = s
		self.num = s	-- Replace string with number, like the clones
		return function ()
			if s == e then
                -- In the case that it's not a range, we want a deep copy for 
                -- the nested arguments table.
                local deep_copy = deepCopy(self)
				s = e + 1 -- then increment the iterator
                return deep_copy
			end
		end
	end
end

return syscall
