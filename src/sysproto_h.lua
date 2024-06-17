#!/usr/libexec/flua
--
-- SPDX-License-Identifier: BSD-2-Clause
--
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

local config = require("config")
local util = require("util")
local bsdio = require("bsdio")

local fh = "test/sysproto.h"

local cfg = {
    syscallprefix = "SYS_"
}


local function gen_sysproto_h(tbl, cfg)
    local s = tbl.syscalls
    local max = 0

    local bio = bsdio:new({ }, fh)
    bio:generated_tag("System call prototypes.")
    bio:pad64(config.abi_changes("pair_64bit"))

    for k, v in pairs(s) do
        local c = v:compat_level()
        if v.num > max then
            max = v.num
        end
        if v.type.STD or
        -- xxx what types are noncompat?
        
        -- xxx compat wrote to a local out and then didn't do anything with it?        
        else -- do nothing

        -- obsolete, old, freebsd-6 and below
        elseif c >= 0 then          -- do nothing
        elseif v.type.RESERVED then -- do nothing
        elseif v.type.UNIMP then    -- do nothing
        
end

-- Entry
if #arg < 1 or #arg > 2 then
	error("usage: " .. arg[0] .. " syscall.master")
end

local sysfile, configfile = arg[1], arg[2]

local cfg_mod = { }

config.merge_global(configfile, cfg, cfg_mod)

-- The parsed syscall table
local tbl = FreeBSDSyscall:new{sysfile = sysfile, config = cfg}

-- XXX FOR SEEING WHAT'S GOING TO NEED TO HAPPEN AND RECONSTRUCTING:
-- noncompat
local nargflags = get_mask({"NOARGS", "NOPROTO", "NODEF"})
	if flags & nargflags == 0 then
	if #funcargs > 0 then
			write_line("sysarg", string.format("struct %s {\n",
			    argalias))
			for _, v in ipairs(funcargs) do
				local argname, argtype = v.name, v.type
				if argtype == "int" and argname == "_pad" and abi_changes("pair_64bit") then
					write_line("sysarg", "#ifdef PAD64_REQUIRED\n")
				end
				write_line("sysarg", string.format(
				    "\tchar %s_l_[PADL_(%s)]; %s %s; char %s_r_[PADR_(%s)];\n",
				    argname, argtype,
				    argtype, argname,
				    argname, argtype))
				if argtype == "int" and argname == "_pad" and abi_changes("pair_64bit") then
					write_line("sysarg", "#endif\n")
				end
			end
			write_line("sysarg", "};\n")
		else
			write_line("sysarg", string.format(
			    "struct %s {\n\tsyscallarg_t dummy;\n};\n", argalias))
		end
	end
	local protoflags = get_mask({"NOPROTO", "NODEF"})
	if flags & protoflags == 0 then
		local sys_prefix = "sys_"
		if funcname == "nosys" or funcname == "lkmnosys" or
		    funcname == "sysarch" or funcname:find("^freebsd") or
		    funcname:find("^linux") then
			sys_prefix = ""
		end
		write_line("sysdcl", string.format(
		    "%s\t%s%s(struct thread *, struct %s *);\n",
		    rettype, sys_prefix, funcname, argalias))
		write_line("sysaue", string.format("#define\t%sAUE_%s\t%s\n",
		    config.syscallprefix, funcalias, auditev))
	end
