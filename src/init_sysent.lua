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
require("test/dump")

-- Globals
local fh = "/dev/null" -- xxx temporary

-- Should be the same as makesyscalls.lua generates, except that we don't bother
-- to align the system call stuff... it's badly broken anyway and looks like crap
-- so we're declaring that a bug and removing all that crazy book-keeping to.
-- If we need to do it, and I hope we don't, I'll just create a string and do
-- #str to figure out how many tabs to add

-- xxx need compat call count

-- Justify the comment column so that comments are all aligned on the same row.
-- There's many ways to align comments, so this is subject to change.
local column = 0
local function setMaxColumn(num)
    if num > column then
        column = num
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

    -- Newline after includes and after this line.
	bio:print("\n#define AS(name) (sizeof(struct name) / sizeof(syscallarg_t))\n")

    -- Write out all the compat directives from compat_options
    -- NOTE: Linux won't have any, so it's skipped as expected.
    for _, v in pairs(config.compat_options) do
        bio:print(string.format([[

#ifdef %s
#define %s(n, name) .sy_narg = n, .sy_call = (sy_call_t *)__CONCAT(%s, name)
#else
#define %s(n, name) .sy_narg = 0, .sy_call = (sy_call_t *)nosys
#endif
]], v.definition, v.flag:lower(), v.prefix, v.flag:lower()))
	end

    -- Add a newline only if there were compat_options
    if config.compat_options ~= nil then
        bio:print("\n")
    end

    bio:print(string.format([[
/* The casts are bogus but will do for now. */
struct sysent %s[] = {accessible
]], config.switchname))

    -- Looping for each system call.
    for k, v in pairs(s) do
        local c = v:compat_level()
        if v.num > max then
            max = v.num
        end

        local argssize = util.processArgsize(v)

        -- Comment is the function alias by default, but may change based on the 
        -- type of system call.
        local comment = v.alias

        -- Creating a string first, to length the string and align comments
        -- based on its length.
        local str = ""

        -- Handle native (non-compat):
        if v:native() then
            str = string.format(
                "\t{ .sy_narg = %s, .sy_call = (sy_call_t *)", 
                argssize)
            setMaxColumn(#str)

            -- Handle SYSMUX flag:
            if v.type.SYSMUX then
                str = str .. string.format(
	        	    "nosys, .sy_auevent = AUE_NULL, " ..
	        	    ".sy_flags = %s, .sy_thrcnt = SY_THR_STATIC },",
	        	    v.cap)
                setMaxColumn(#str)

            -- Handle NOSTD flag:
            elseif v.type.NOSTD then
    
	        	str = str .. string.format(
	        	    "lkmressys, .sy_auevent = AUE_NULL, " ..
	        	    ".sy_flags = %s, .sy_thrcnt = SY_THR_ABSENT },",
	        	    v.cap)
                setMaxColumn(#str)
                bio:print(str)

            -- Handle rest of non-compat:
            elseif v.type.STD or
                   v.type.NODEF or
                   v.type.NOARGS or
                   v.type.NOPROTO then
	            if v.name == "nosys" or 
                   v.name == "lkmnosys" or
                   v.name == "sysarch" or
                   v.name:find("^freebsd") or
	        	   v.name:find("^linux") then
                    str = str .. string.format(
                        "%s, .sy_auevent = %s, .sy_flags = %s, " .. 
                        ".sy_thrcnt = %s },",
	        		    v:symbol(), v.audit, v.cap, v.thr)
                    setMaxColumn(#str)
	        	else
                    str = str .. string.format(
                        "sys_%s, .sy_auevent = %s, .sy_flags = %s, " .. 
                        ".sy_thrcnt = %s },",
	        		    v:symbol(), v.audit, v.cap, v.thr)
                    setMaxColumn(#str)
	        	end

                else
                    -- Assume something went wrong.
                    util.abort(1, 
                        "Unable to generate system switch for system call: " .. 
                        v.name)
                end

        -- Handle compatibility (everything >= FREEBSD3):
        elseif c >= 3 then
            local flag = config.lookupCompatOption(c, flag)
            flag = flag:lower()
            local descr = config.lookupCompatOption(c, descr)

            if v.type.NOSTD then
                str = string.format(
	    	        "\t{ .sy_narg = %s, .sy_call = (sy_call_t *)%s, " ..
	    	        ".sy_auevent = %s, .sy_flags = 0, " ..
	    	        ".sy_thrcnt = SY_THR_ABSENT },",
	    	        "0", "lkmressys", "AUE_NULL")
                setMaxColumn(#str)
	        else
	    	    str = string.format(
	    	        "\t{ %s(%s,%s), .sy_auevent = %s, .sy_flags = %s, " ..
                    ".sy_thrcnt = %s },",
	    	        flag, argssize, v:symbol(), v.audit, v.cap, v.thr)
                setMaxColumn(#str)
            end
            comment = descr .. " " .. v.alias

        -- Handle obsolete:
        elseif v.type.OBSOL then
	        str = string.format(
                "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
	            ".sy_auevent = AUE_NULL, .sy_flags = 0, " ..
                ".sy_thrcnt = SY_THR_ABSENT },")
            setMaxColumn(#str)
            comment = "obsolete " .. v.alias
        
        -- Handle unimplemented:
        -- xxx make sure there's no skipped syscalls and range is correct
        elseif v.type.UNIMP then
		    str = string.format(
		        "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
		        ".sy_auevent = AUE_NULL, .sy_flags = 0, " ..
		        ".sy_thrcnt = SY_THR_ABSENT },")
            setMaxColumn(#str)
            comment = "" -- xxx not seeing where there is right now

        -- Handle reserved:
        -- xxx make sure there's no skipped syscalls and range is correct
        elseif v.type.RESERVED then
            str = string.format(
		        "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
		        ".sy_auevent = AUE_NULL, .sy_flags = 0, " ..
		        ".sy_thrcnt = SY_THR_ABSENT },")
            setMaxColumn(#str)
            comment = "reserved for local use"
            
        else
            -- do nothing
        end

        bio:print(str)
        local tabs = (column - #str) / 4
        for _ = 1, tabs do
            bio:print("\t")
        end
	    bio:print(string.format("/* %d = %s */\n", 
            v.num, comment))
    end

    -- End
    bio:print("};")
end

-- Entry

if #arg < 1 or #arg > 2 then -- xxx subject to change
	error("usage: " .. arg[0] .. " syscall.master")
end

local sysfile, configfile = arg[1], arg[2]

config.merge(configfile)
config.mergeCompat()
config.mergeCapability()

-- The parsed syscall table
local tbl = FreeBSDSyscall:new{sysfile = sysfile, config = config}

genInitSysent(tbl, config)
