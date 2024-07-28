#!/usr/libexec/flua
--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2023 Warner Losh <imp@bsdimp.com>
-- Copyright (c) 2024 Tyler Baxter <agge@FreeBSD.org>
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

-- Setup to be a module, or ran as its own script.
local syscall_h = {}

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
-- File has not been decided yet; config will decide file. Default defined as
-- null
syscall_h.file = "/dev/null"

-- Libc has all the STD, NOSTD and SYSMUX system calls in it, as well as
-- replaced system calls dating back to FreeBSD 7. We are lucky that the
-- system call filename is just the base symbol name for it.
function syscall_h.generate(tbl, config, fh)
    -- Grab the master syscalls table, and prepare bookkeeping for the max
    -- syscall number.
    local s = tbl.syscalls
    local max = 0

    -- Init the bsdio object, has macros and procedures for LSG specific io.
    local bio = bsdio:new({}, fh) 

    -- Write the generated tag.
	bio:generated("System call numbers.")

	for k, v in pairs(s) do
		local c = v:compat_level()
		if v.num > max then
			max = v.num
		end
		if  v.type.STD or
			v.type.NOSTD or
			v.type.SYSMUX or
			c >= 7 then
			bio:write(string.format("#define\t%s%s\t%d\n", 
                config.syscallprefix, v:symbol(), v.num))
		elseif c >= 0 then
			local s
			if c == 0 then
				s = "obsolete"
			elseif c == 3 then
				s = "old"
			else
				s = "freebsd" .. c
			end
			bio:write(string.format("\t\t\t\t/* %d is %s %s */\n", 
                v.num, s, v.name))
		elseif v.type.RESERVED then
			bio:write(string.format("\t\t\t\t/* %d is reserved */\n", v.num))
		elseif v.type.UNIMP then
			bio:write(string.format("\t\t\t\t/* %d is unimplemented %s */\n", 
                v.num, v.name))
		else -- do nothing
		end
	end
	bio:write(string.format("#define\t%sMAXSYSCALL\t%d", 
        config.syscallprefix, max + 1))
end

-- Check if the script is run directly
if not pcall(debug.getlocal, 4, 1) then
    -- Entry of script
    if #arg < 1 or #arg > 2 then
    	error("usage: " .. arg[0] .. " syscall.master")
    end
    
    local sysfile, configfile = arg[1], arg[2]
    
    config.merge(configfile)
    config.mergeCompat()
    config.mergeCapability()
    config.mergeChangesAbi()
    
    -- The parsed syscall table
    local tbl = FreeBSDSyscall:new{sysfile = sysfile, config = config}
   
    syscall_h.file = config.syshdr -- change file here
    syscall_h.generate(tbl, config, syscall_h.file)
end

-- Return the module
return syscall_h
