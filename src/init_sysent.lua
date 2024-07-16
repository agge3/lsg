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

-- xxx needs attention, semi-working
local function alignSysentComment(column)
    io.write("\t")
    column = column + 8 - column % 8
    while column < 56 do
        io.write("\t")
        column = column + 8
    end
end

local function lookupCompatFlag(compat_options, compatlevel)
    for _, v in pairs(compat_options) do
        if v.compatlevel == compatlevel then
            return v.flag
        end
    end
    return nil
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
struct sysent %s[] = {
]], config.switchname))

    -- Keep track of columns to align sysent comment.
    local column

    for k, v in pairs(s) do
        local c = v:compat_level()
        if v.num > max then
            max = v.num
        end

        --dump(v.args)

        local argssize = util.processArgsize(v)
        local comment = v.alias

        -- Handle native (non-compatibility):
        -- NOTE: If the system call's name matches its symbol then it's a native
        -- system call.
        if v.name == v:symbol() then

	        bio:print(string.format("\t{ .sy_narg = %s, .sy_call = (sy_call_t *)", 
                argssize))
            column = 8 + 2 + #argssize + 15

            -- Handle SYSMUX flag.
            if v.type.SYSMUX then

	        	bio:print(string.format(
	        	    "nosys, .sy_auevent = AUE_NULL, " ..
	        	    ".sy_flags = %s, .sy_thrcnt = SY_THR_STATIC },",
	        	    v.cap))
                column = column + #"nosys" + #"AUE_NULL" + 3

                -- xxx better organize this repeat line
                alignSysentComment(column)

            -- Handle NOSTD flag. 
            elseif v.type.NOSTD then
    
	        	bio:print(string.format(
	        	    "lkmressys, .sy_auevent = AUE_NULL, " ..
	        	    ".sy_flags = %s, .sy_thrcnt = SY_THR_ABSENT },",
	        	    v.cap))
		        column = column + #"lkmressys" + #"AUE_NULL" + 3

                alignSysentComment(column)

            -- Handle rest of non-compatability.
            -- XXX everything is looking reasonably well. NOT handling args 
            -- correctly.
            elseif v.type.STD or
                   v.type.NODEF or
                   v.type.NOARGS or
                   v.type.NOPROTO then

                -- xxx not sure these find call will work
	        	if v.name == "nosys" or 
                   v.name == "lkmnosys" or
                   v.name == "sysarch" or
                   v.name:find("^freebsd") or
	        	   v.name:find("^linux") then
	        	    bio:print(string.format("%s, .sy_auevent = %s, .sy_flags = %s, .sy_thrcnt = %s },",
	        		    v:symbol(), v.audit, v.cap, v.thr))
                    column = column + #v.name + #v.audit + #v.cap + 3
	        	else
	        		bio:print(string.format("sys_%s, .sy_auevent = %s, .sy_flags = %s, .sy_thrcnt = %s },",
	        		    v:symbol(), v.audit, v.cap, v.thr))
                    column = column + #v.name + #v.audit + #v.cap + 7
	        	end
                
                alignSysentComment(column)

                else
                    -- assume something went wrong
                    util.abort(1, "Unable to generate system switch table entry for system call: " .. v.name)
                end


        -- Handle compatibility (everything >= FREEBSD3):
        elseif c >= 3 then
            local flag = lookupCompatFlag(config.compat_options, c)
            -- Flag is uppercase by default.
            flag = flag:lower()
            local descr = ""
            if v.type.NOSTD then
                bio:print(string.format(
	    	        "\t{ .sy_narg = %s, .sy_call = (sy_call_t *)%s, " ..
	    	        ".sy_auevent = %s, .sy_flags = 0, " ..
	    	        ".sy_thrcnt = SY_THR_ABSENT },",
	    	        "0", "lkmressys", "AUE_NULL"))
	    	    alignSysentComment(8 + 2 + #"0" + 15 + #"lkmressys" +
	    	        #"AUE_NULL" + 3)
	        else
	    	    bio:print(string.format(
	    	        "\t{ %s(%s,%s), .sy_auevent = %s, .sy_flags = %s, .sy_thrcnt = %s },",
	    	        flag, argssize, v:symbol(), v.audit, v.cap, v.thr))
	    	    alignSysentComment(8 + 9 + #argssize + 1 + #v:symbol() +
	    	    #v.audit + #v.cap + 4)
            end
            comment = descr .. " " .. v.alias

        -- Handle obsolete:
        elseif v.type.OBSOL then
	        bio:print(
	            "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
	            ".sy_auevent = AUE_NULL, .sy_flags = 0, .sy_thrcnt = SY_THR_ABSENT },")
	        -- xxx comment
            local xxx_comment = "" 
            local comment = "obsolete " .. xxx_comment
        
        -- Handle unimplemented:
        -- xxx make sure there's no skipped syscalls and range is correct
        elseif v.type.UNIMP then
            local unimp = "" -- xxx not seeing where there is right now
		    bio:print(string.format(
		        "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
		        ".sy_auevent = AUE_NULL, .sy_flags = 0, " ..
		        ".sy_thrcnt = SY_THR_ABSENT },\t\t\t"))
            comment = unimp

        -- Handle reserved:
        -- xxx make sure there's no skipped syscalls and range is correct
        elseif v.type.RESERVED then
            local reserved = "reserved for local use"
            bio:print(string.format(
		        "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
		        ".sy_auevent = AUE_NULL, .sy_flags = 0, " ..
		        ".sy_thrcnt = SY_THR_ABSENT },\t\t\t"))
            comment = reserved

        -- XXX have range available
            
        else -- do nothing
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
