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

-- Globals

-- Default configuration; any of these may get replaced by a configuration file
-- optionally specified. A lot of these are passed into the fbsd_sys parser and
-- the bsd_user code generator A bit tricky because a lot of the inherited code
-- has a global config table that it referrs to deep in the call tree... need to
-- make sure that all that code is converted to using one local to the object.
local cfg = {

}

local cfg_mod = {

}

local fh = "/dev/null" -- xxx temporary

-- Should be the same as makesyscalls.lua generates, except that we don't bother
-- to align the system call stuff... it's badly broken anyway and looks like crap
-- so we're declaring that a bug and removing all that crazy book-keeping to.
-- If we need to do it, and I hope we don't, I'll just create a string and do
-- #str to figure out how many tabs to add

-- xxx need compat call count

local function gen_init_sysent(tbl, config)
    local s = tbl.syscalls
    local max = 0
    local bio = bsdio:new({ }, fh) 

    bio:generated("System call switch table.")

	bio:print(tbl.includes)
	bio:print("\n#define AS(name) (sizeof(struct name) / sizeof(syscallarg_t))")

	-- xxx compat_options doesn't exist yet
    for _, v in pairs(tbl.compat_options) do
		if v.count > 0 then
			bio:print(string.format([[

#ifdef %s
#define %s(n, name) .sy_narg = n, .sy_call = (sy_call_t *)__CONCAT(%s, name)
#else
#define %s(n, name) .sy_narg = 0, .sy_call = (sy_call_t *)nosys
#endif
]], v.definition, v.flag:lower(), v.prefix, v.flag:lower()))
		end
	end

	-- xxx switchname doesn't exist yet
	bio:print(string.format([[

/* The casts are bogus but will do for now. */
struct sysent %s[] = {
]], config.switchname))

    bio:print(tbl.defines)

	-- xxx for each syscall
    for k, v in pairs(s) do
	    -- xxx handle non-compat
	    -- xxx argsize, sysflags, funcname, auditev, thr_flag
	    bio:print(string.format("\t{ .sy_narg = %s, .sy_call = (sy_call_t *)", 
                argssize)) -- xxx 

	    -- mux flag
        if v.type.SYSMUX then
	    	bio:print(string.format(
	    	    "nosys, .sy_auevent = AUE_NULL, " ..
	    	    ".sy_flags = %s, .sy_thrcnt = SY_THR_STATIC },",
	    	    v.cap))

        else if v.type.NOSTD then
	    	bio:print(string.format(
	    	    "lkmressys, .sy_auevent = AUE_NULL, " ..
	    	    ".sy_flags = %s, .sy_thrcnt = SY_THR_ABSENT },",
	    	    v.cap))
	    else
            -- xxx not sure these find call will work
	    	if v.name == "nosys" or v.name == "lkmnosys" or
               v.name == "sysarch" or v.name:find("^freebsd") or
	    	   v.name:find("^linux") then
	    	    bio:write(string.format(
                    "%s, .sy_auevent = %s, .sy_flags = %s, .sy_thrcnt = %s },",
	    		    v.name, v.audit, v.cap, v.thr))
	    	else
	    		bio:write(string.format(
	    		    "sys_%s, .sy_auevent = %s, .sy_flags = %s, .sy_thrcnt = %s },",
	    		    v.name, v.audit, v.cap, v.thr))
	    	end
	    end

	    -- xxx alias
        bio:write(string.format("/* %d = %s */\n",
	        v.num, v.alias))

	    -- xxx handle obsol
	    bio:write(
	        "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
	        ".sy_auevent = AUE_NULL, .sy_flags = 0, .sy_thrcnt = SY_THR_ABSENT },")

	    -- xxx comment
        bio:write("sysent", string.format("/* %d = obsolete %s */\n",
	        v.num, v.comment))

	    -- xxx handle compat
        if v.type.NOSTD then
	    	bio:write(string.format(
	    	    "\t{ .sy_narg = %s, .sy_call = (sy_call_t *)%s, " ..
	    	    ".sy_auevent = %s, .sy_flags = 0, " ..
	    	    ".sy_thrcnt = SY_THR_ABSENT },",
	    	    "0", "lkmressys", "AUE_NULL"))
	    else
            -- xxx wrap?? argsize
	    	bio:write(string.format(
	    	    "\t{ %s(%s,%s), .sy_auevent = %s, .sy_flags = %s, .sy_thrcnt = %s },",
	    	    wrap, argssize, v.name, v.audit, v.cap, v.thr))
	    end

	    -- xxx descr alias
        bio:write(string.format("/* %d = %s %s */\n",
	        v.num, descr, v.alias))

	    -- xxx handle unimpl
        -- XXX have range available
	    if sysstart == nil and sysend == nil then
	    	sysstart = tonumber(sysnum)
	    	sysend = tonumber(sysnum)
	    end

	    sysnum = sysstart
	    while sysnum <= sysend do
	    	bio:write(string.format(
	    	    "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
	    	    ".sy_auevent = AUE_NULL, .sy_flags = 0, " ..
	    	    ".sy_thrcnt = SY_THR_ABSENT },\t\t\t/* %d = %s */\n",
	    	    v.num, v.comment))
	    	sysnum = sysnum + 1
	    end
    end

	-- xxx end of foreach

	print("};")
end

-- Entry

if #arg < 1 or #arg > 2 then
	error("usage: " .. arg[0] .. " syscall.master")
end

local sysfile, configfile = arg[1], arg[2]

config.merge_global(fh, cfg, cfg_mod)

-- The parsed syscall table
local tbl = FreeBSDSyscall:new{sysfile = sysfile, config = config}

gen_init_sysent(tbl, config)
