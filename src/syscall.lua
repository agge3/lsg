--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2023 Warner Losh <imp@bsdimp.com>
-- Copyright (c) 2024 Tyler Baxter <agge@FreeBSD.org>
--

scarg = require("scarg")
scret = require("scret")
util = require("util")

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

-- All compat option entries should have five entries:
--	definition: The preprocessor macro that will be set for this
--	compatlevel: The level this compatibility should be included at.  This
--	    generally represents the version of FreeBSD that it is compatible
--	    with, but ultimately it's just the level of mincompat in which it's
--	    included.
--	flag: The name of the flag in syscalls.master.
--	prefix: The prefix to use for _args and syscall prototype.  This will be
--	    used as-is, without "_" or any other character appended.
--	descr: The description of this compat option in init_sysent.c comments.
-- The special "stdcompat" entry will cause the other five to be autogenerated.
local compat_option_sets = {
	native = {
		{
			definition = "COMPAT_43",
			compatlevel = 3,
			flag = "COMPAT",
			prefix = "o",
			descr = "old",
		},
		{ stdcompat = "FREEBSD4" },
		{ stdcompat = "FREEBSD6" },
		{ stdcompat = "FREEBSD7" },
		{ stdcompat = "FREEBSD10" },
		{ stdcompat = "FREEBSD11" },
		{ stdcompat = "FREEBSD12" },
		{ stdcompat = "FREEBSD13" },
	},
}

-- Checks against both ABI changes flag or if configuration file has specified 
-- no ABI changes.
local function checkAbi()
    -- xxx this needs to be reworked
    if config.changes_abi then
        -- argalias should be:
    	--   COMPAT_PREFIX + ABI Prefix + funcname
    	--argprefix = config.abi_func_prefix
   	    --funcprefix = config.abi_func_prefix

    	-- XXX need clarification on if these are the same
        --funcalias = funcprefix .. funcname
        --argalias
	    --self.altname = words[5]
	    --self.alttag = words[6]
	    --self.altrtyp = words[7]

    	--noproto = false
    end
end

--
-- Processes the thread flag for the system call.
-- RETURN: String thr, the appropriate thread flag
--
local function processThr(t)
    local str = "SY_THR_STATIC"
    for k, v in pairs(t) do
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
local function processCap(name, t)
    -- xxx broken right now, but will be sorted out after handling the cap stuff
    --local str = "0"
    --if config.capenabled[name] ~= nil or
    --   config.capenabled[util.stripAbiPrefix(name)] ~= nil then
    --    str = "SYF_CAPENABLED"
    --else
    --    for k, v in pairs(t) do
    --        if k == "CAPENABLED" then
    --            str = "SYF_CAPENABLED"
    --        end
    --    end
    --end
    --return str
end

-- XXX need to sort out how to do compat stuff...
-- native is the only compat thing
-- Also need to figure out the different other things that 'filter' system calls
-- since the abi32 stuff does that.

-- Validates a system call's type, aborts if unknown.
local function checkType(line, t)
	for k, v in pairs(t) do
	    if not syscall.known_flags[k] and not
            k:match("^COMPAT") then
			util.abort(1, "Bad type: " .. k)
		end
	end
end

-- If there are ABI changes from native, process the system call to match the
-- expected ABI.
local function processAbiChanges()
    if config["changes_abi"] then
        -- argalias should be:
        --   COMPAT_PREFIX + ABI Prefix + funcname
    	self.argprefix = config["abi_func_prefix"] -- xxx issue here
    	self.prefix = config["abi_func_prefix"]
    	self.alias = self.prefix .. self.name
    	return false -- xxx noproto = false,  trace better
    end
    return true
end

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
    
-- Also, where to put validation of no skipped syscall #? XXX

-- Validate that there's no skipped system call.
function syscall:validate(prev)
    -- xxx will need to have max range with this approach
    if (self.num ~= prev + 1) then
        abort(1, "Syscall number out of sync, missing syscall number " .. prev)
    end

    -- xxx rework this. maybe just peek last and confirm we're on track
    --if sysnum:find("-") then
    --	sysstart, sysend = sysnum:match("^([%d]+)-([%d]+)$")
    --	if sysstart == nil or sysend == nil then
    --		abort(1, "Malformed range: " .. sysnum)
    --	end
    --	sysnum = nil
    --	sysstart = tonumber(sysstart)
    --	sysend = tonumber(sysend)
    --	if sysstart ~= maxsyscall + 1 then
    --		abort(1, "syscall number out of sync, missing " ..
    --		    maxsyscall + 1)
    --	end
    --else
    --	sysnum = tonumber(sysnum)
    --	if sysnum ~= maxsyscall + 1 then
    --		abort(1, "syscall number out of sync, missing " ..
    --		    maxsyscall + 1)
    --	end
    --end
end

--
-- Adds the definition for the system call.
-- NOTE: Is guarded by the system call number ~= nil
-- RETURN: TRUE, if the definition was added. FALSE, if not
--
function syscall:addDef(line, words)
    if self.num == nil then
        -- sort out range somehow XXX
	    self.num = words[1]
	    self.audit = words[2]
	    self.type = util.setFromString(words[3], "[^|]+")
	    checkType(line, self.type)
        self.thr = processThr(self.type)
	    self.name = words[4]
        self.cap = processCap(self.name, self.type)
	    -- These next three are optional, and either all present or all absent
	    self.altname = words[5]
	    self.alttag = words[6]
	    self.altrtyp = words[7]
	    return self.name == "{"
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
        arg = nil -- nil the reference to trigger the finalizer
        return true
    end
    return false
end

--
-- Confirm that the system call was added succesfully, ABORT if not.
-- NOTE: Is guarded by validation of the argument(s).
-- RETURN: TRUE, if added succesfully. FALSE (or ABORT), if not
--
function syscall:isAdded(line)
    if self.expect_rbrace then
  	    -- state wrapping up, can only get } here
	    if not line:match("}$") then
	    	util.abort(1, "Expected '}' found '" .. line .. "' instead.")
	    end
        return true
    end
    return false
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
        return false -- definition added, keep going
    end
    if self:addFunc(line, words) then
        return false -- function added, keep going
    end
    if self:addArgs(line) then
        return false -- arguments added, keep going
    end
    return self:isAdded(line) -- final validation, before adding
end

function syscall:new(obj)
	obj = obj or { }
	setmetatable(obj, self)
	self.__index = self

	self.expect_rbrace = false
	self.args = { }

	return obj
end

--
-- Make a copy (a shallow one is fine) of `self` and replace
-- the system call number (which is likely a range) with num
-- (which should be a number)
--
function syscall:clone(num)
	local obj = syscall:new(obj)

	-- shallow copy
	for k, v in pairs(self) do
		obj[k] = v
	end
	obj.num = num	-- except override range
	return obj
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
		s, e = string.match(self.num, "(%d+)%-(%d)")
		return function ()
			if s <= e then
				s = s + 1
				return self:clone(s - 1)
			end
		end
	else
		e = s
		self.num = s	-- Replace string with number, like the clones
		return function ()
			if s == e then
				s = e + 1
				return self
			end
		end
	end
end

return syscall
