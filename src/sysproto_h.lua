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

local config = require("config")    -- Common config file mgt
local util = require("util")
local bsdio = require("bsdio")

-- Globals

local sysproto = "" .. ".h"
local sysproto_h = "" .. "_SYSPROTO_H_"

local function genSysprotoH(tbl, config)
    -- Grab the master syscalls table, and prepare bookkeeping for the max
    -- syscall number.
    local s = tbl.syscalls
    local max = 0

    -- Init the bsdio object, has macros and procedures for LSG specific io.
    local bio = bsdio:new({ }, fh) 

    -- Write the generated tag.
    bio:generated("System call prototypes.")
    
    -- pad64() is an io macro that will pad based on the result of 
    -- abi_changes().
    bio:pad64(config.abi_changes("pair_64bit"))

    for k, v in pairs(s) do
        local c = v:compat_level()
        if v.num > max then
            max = v.num
        end

        -- Handle non-compatability.
        -- xxx going to convert these to *not* negations, following flow of
        -- makesyscalls.lua for now.
        if not v.type.NOARGS or
           not v.type.NOPROTO or
           not v.type.NODEF then
            if #v.args > 0 then
                -- fh = sysarg
                bio:write(string.format("struct %s {\n",
			        v.alias))
			    for _, v in ipairs(v.args) do -- XXX
				    if v.type == "int" and v.name == "_pad" then 
                        bio:pad(config.abiChanges("pair_64bit"))
                        -- xxx expected: "#ifdef PAD64_REQUIRED\n"
                    end
				    bio:write(string.format(
                        "\tchar %s_l_[PADL_(%s)]; %s %s; char %s_r_[PADR_(%s)];\n",
                        v.name, v.type,
				        v.type, v.name,
				        v.name, v.type))
                    if v.type == "int" and v.name = "_pad" then
                        bio:pad(config.abiChanges("pair_64bit"))
                        -- xxx expected: "#endif\n"
				end
                bio:write("};\n")
            else
                -- fh = sysarg
                bio:write(string.format(
			        "struct %s {\n\tsyscallarg_t dummy;\n};\n", v.alias))
            end
        else if not v.type.NOPROTO or
                not v.type.NODEF then
            local sys_prefix = "sys_"
            -- xxx generalize this condition, it can be reused and named 
            --clear what it's implying
            if v.name == "nosys" or v.name == "lkmnosys" or
               v.name == "sysarch" or v.name:find("^freebsd") or
               v.name:find("^linux") then
                sys_prefix = ""
            end
            -- fh = sysdcl
            bio:write(string.format(
                "%s\t%s%s(struct thread *, struct %s *);\n",
		        v.rettype, v.prefix, v.name, v.alias))
            -- fh = sysaue
		    bio:write(string.format("#define\t%sAUE_%s\t%s\n",
		        config.syscallprefix, v.alias, v.audit)) 
        end
        -- noncompat done
        


                   

        elseif c >=7 then
        -- xxx do nothing for now, handle compat -- trace "out" in 
        -- makesyscalls.lua 
        else
        -- xxx everything else is do nothing for sysproto.h
        end
    end
end

-- Entry

if #arg < 1 or #arg > 2 then
	error("usage: " .. arg[0] .. " syscall.master")
end

local sysfile, configfile = arg[1], arg[2]

config.merge(config)

-- The parsed syscall table
local tbl = FreeBSDSyscall:new{sysfile = sysfile, config = config}

genSysprotoH(tbl, config)
