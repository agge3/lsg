#!/usr/libexec/flua
--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2023 Warner Losh <imp@bsdimp.com>
--
--
-- Thanks to Kyle Evans for his makesyscall.lua in FreeBSD which served as
-- inspiration for this, and as a source of code at times.
--
-- SPDX-License-Identifier: BSD-2-Clause-FreeBSD
--
-- Copyright (c) 2019 Kyle Evans <kevans@FreeBSD.org>
--

-- We generally assume that this script will be run by flua, however we've
-- carefully crafted modules for it that mimic interfaces provided by modules
-- available in ports.  Currently, this script is compatible with lua from
-- ports along with the compatible luafilesystem and lua-posix modules.

-- When we have a path, add it to the package.path (. is already in the list)
if arg[0]:match("/") then
	local a = arg[0]:gsub("/[^/]+.lua$", "")
	package.path = package.path .. ";" .. a .. "/?.lua"
end

-- The FreeBSD syscall generator
local FreeBSDSyscall = require("freebsd-syscall")

local config = require("config")		-- Common config file mgt
local util = require("util")
local bsdio = require("bsdio")

-- Globals

local fh = "/dev/null" -- xxx temporary

-- Should be the same as makesyscalls.lua generates, except that we don't bother
-- to align the system call stuff... it's badly broken anyway and looks like crap
-- so we're declaring that a bug and removing all that crazy book-keeping to.
-- If we need to do it, and I hope we don't, I'll just create a string and do
-- #str to figure out how many tabs to add

-- xxx need compat call count

-- xxx needs attention, semi-working
local function alignSysentComment(column)
    io.write("\t")
    column = column + 8 - column % 8
    while column < 56 do
        io.write("\t")
        column = column + 8
    end
end

local function genInitSysent(tbl, config)
    -- Grab the master syscalls table, and prepare bookkeeping for the max
    -- syscall number.
    local s = tbl.syscalls
    local max = 0

    -- Init the bsdio object, has macros and procedures for LSG specific io.
    local bio = bsdio:new({ }, fh) 

    -- Write the generated tag.
    bio:generated("System call switch table.")

	bio:print(tbl.includes)
	bio:print("#define AS(name) (sizeof(struct name) / sizeof(syscallarg_t))")

    -- Keep track of columns to align sysent comment.
    local column

    for k, v in pairs(s) do
        local c = v:compat_level()
        if v.num > max then
            max = v.num
        end

        -- xxx temporary
        if v.alias == nil then
            v.alias = "broken alias"
        end

        -- xxx argssize - seems like this could be made reusable, where to put?
        local argssize
        if #v.args > 0 or v.type.NODEF then
            argssize = "AS(" .. v.arg_alias .. ")"
        else
            argssize = "0"
        end

        -- Handle non-compatability. 

        -- Handle SYSMUX flag.
        if v.type.SYSMUX then
	        bio:print(string.format("\t{ .sy_narg = %s, .sy_call = (sy_call_t *)", 
                argssize))
            column = 8 + 2 + #argssize + 15
	    	bio:print(string.format(
	    	    "nosys, .sy_auevent = AUE_NULL, " ..
	    	    ".sy_flags = %s, .sy_thrcnt = SY_THR_STATIC },",
	    	    v.cap))
            column = column + #"nosys" + #"AUE_NULL" + 3
            -- xxx better organize this repeat line
            alignSysentComment(column)
            bio:print(string.format("/* %d = %s */\n",
	            v.num, v.alias))

        -- Handle NOSTD flag. 
        elseif v.type.NOSTD then
            -- xxx better organize this repeat line
	        bio:print(string.format("\t{ .sy_narg = %s, .sy_call = (sy_call_t *)", 
                argssize))
            column = 8 + 2 + #argssize + 15
	    	bio:print(string.format(
	    	    "lkmressys, .sy_auevent = AUE_NULL, " ..
	    	    ".sy_flags = %s, .sy_thrcnt = SY_THR_ABSENT },",
	    	    v.cap))
		    column = column + #"lkmressys" + #"AUE_NULL" + 3
            alignSysentComment(column)
            -- xxx better organize this repeat line
            bio:print(string.format("/* %d = %s */\n",
	            v.num, v.alias))

        -- Handle rest of non-compatability.
        elseif v.type.STD or
               v.type.NODEF or
               v.type.NOARGS or
               v.type.NOPROTO then
            -- xxx better organize this repeat line
	        bio:print(string.format("\t{ .sy_narg = %s, .sy_call = (sy_call_t *)", 
                argssize))
            column = 8 + 2 + #argssize + 15

            -- xxx not sure these find call will work
	    	if v.name == "nosys" or 
               v.name == "lkmnosys" or
               v.name == "sysarch" or
               v.name:find("^freebsd") or
	    	   v.name:find("^linux") then
	    	    bio:print(string.format("%s, .sy_auevent = %s, .sy_flags = %s, .sy_thrcnt = %s },",
	    		    v.name, v.audit, v.cap, v.thr))
                column = column + #v.name + #v.audit + #v.cap + 3
	    	else
	    		bio:print(string.format("sys_%s, .sy_auevent = %s, .sy_flags = %s, .sy_thrcnt = %s },",
	    		    v.name, v.audit, v.cap, v.thr))
                column = column + #v.name + #v.audit + #v.cap + 7
	    	end
            
            alignSysentComment(column)
            -- xxx better organize this repeat line
            bio:print(string.format("/* %d = %s */\n",
	            v.num, v.alias))

        -- Handle compatability.
        elseif c >= 7 then
            -- xxx needs further attention on sorting
            if v.type.NOSTD then
	        	bio:print(string.format(
	        	    "\t{ .sy_narg = %s, .sy_call = (sy_call_t *)%s, " ..
	        	    ".sy_auevent = %s, .sy_flags = 0, " ..
	        	    ".sy_thrcnt = SY_THR_ABSENT },",
	        	    "0", "lkmressys", "AUE_NULL"))
	        else
                -- xxx wrap
                local wrap = ""
	        	bio:print(string.format(
	        	    "\t{ %s(%s,%s), .sy_auevent = %s, .sy_flags = %s, .sy_thrcnt = %s },",
	        	    wrap, argssize, v.name, v.audit, v.cap, v.thr))
	        end

            -- xxx descr
            local descr = ""
            bio:print(string.format("/* %d = %s %s */\n",
	            v.num, descr, v.alias))

        -- Handle different compatability options.
        elseif c >= 0 then
        -- xxx needs attention!
           	local s
			if c == 0 then
				s = "obsolete"
			elseif c == 3 then
				s = "old"
			else
				s = "freebsd" .. c
			end 
        
        -- Handle obsolete.
        elseif v.type.OBSOL then
	        bio:print(
	            "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
	            ".sy_auevent = AUE_NULL, .sy_flags = 0, .sy_thrcnt = SY_THR_ABSENT },")
	        -- xxx comment
            local comment = ""
            bio:print(string.format("/* %d = obsolete %s */\n",
	            v.num, comment))

        -- Handle reserved.
        elseif v.type.RESERVED then
        -- xxx reserved goes here

        -- Handle unimplemented.
        elseif v.type.UNIMP then
        -- XXX have range available
        -- xxx this likely will be done in freebsd-syscall
	        --if sysstart == nil and sysend == nil then
	        --	sysstart = tonumber(sysnum)
	        --	sysend = tonumber(sysnum)
	        --end

	        --sysnum = sysstart
	        --while sysnum <= sysend do
	        --	bio:print(string.format(
	        --	    "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
	        --	    ".sy_auevent = AUE_NULL, .sy_flags = 0, " ..
	        --	    ".sy_thrcnt = SY_THR_ABSENT },\t\t\t/* %d = %s */\n",
	        --	    v.num, v.comment))
	        --	sysnum = sysnum + 1
	        --end

        else -- do nothing
        end
    end

    -- End
    print("};")
end

-- Entry

if #arg < 1 or #arg > 2 then -- xxx subject to change
	error("usage: " .. arg[0] .. " syscall.master")
end

local sysfile, configfile = arg[1], arg[2]

config.merge(configfile)
config.mergeCapability()


-- The parsed syscall table
local tbl = FreeBSDSyscall:new{sysfile = sysfile, config = config}

genInitSysent(tbl, config)


-- xxx THINGS THAT STILL NEED ATTENTION:	
-- xxx compat_options doesn't exist yet
--    for _, v in pairs(tbl.compat_options) do
--		if v.count > 0 then
--			bio:print(string.format([[
--
--#ifdef %s
--#define %s(n, name) .sy_narg = n, .sy_call = (sy_call_t *)__CONCAT(%s, name)
--#else
--#define %s(n, name) .sy_narg = 0, .sy_call = (sy_call_t *)nosys
--#endif
--]], v.definition, v.flag:lower(), v.prefix, v.flag:lower()))
--		end
--	end
--
--	bio:print(string.format([[
--
--/* The casts are bogus but will do for now. */
--struct sysent %s[] = {
--]], config.switchname))
--
--    bio:print(tbl.defines)
