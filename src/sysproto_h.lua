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

local fh = "/dev/null"

local sysproto = "" .. ".h"
local sysproto_h = "" .. "_SYSPROTO_H_"

-- xxx tricky generation here, a lot of pieces in different places at different 
-- times
local function genSysprotoH(tbl, config)
    -- Grab the master syscalls table, and prepare bookkeeping for the max
    -- syscall number.
    local s = tbl.syscalls
    local max = 0

    -- Init the bsdio object, has macros and procedures for LSG specific io.
    local bio = bsdio:new({}, fh) 

    --local main = bsdio:new({}, fh)
    --local dcl = bsdio:new({}, fh)
    --local aue = bsdio:new({}, fh)
    --local compat = bsdio:new({}, fh)

    -- Write the generated tag.
    bio:generated("System call prototypes.")

    -- Write out the preamble.
    bio:print([[
#ifndef %s
#define	%s

#include <sys/types.h>
#include <sys/signal.h>
#include <sys/cpuset.h>
#include <sys/domainset.h>
#include <sys/_ffcounter.h>
#include <sys/_semaphore.h>
#include <sys/ucontext.h>
#include <sys/wait.h>

#include <bsm/audit_kevents.h>

struct proc;

struct thread;

#define	PAD_(t)	(sizeof(syscallarg_t) <= sizeof(t) ? \
		0 : sizeof(syscallarg_t) - sizeof(t))

#if BYTE_ORDER == LITTLE_ENDIAN
#define	PADL_(t)	0
#define	PADR_(t)	PAD_(t)
#else
#define	PADL_(t)	PAD_(t)
#define	PADR_(t)	0
#endif

]], config.sysproto_h, config.sysproto_h)
    
    -- pad64() is an io macro that will pad based on the result of 
    -- abi_changes().
    bio:pad64(config.abiChanges("pair_64bit"))

    for k, v in pairs(s) do
        local c = v:compat_level()
        if v.num > max then
            max = v.num
        end

        -- Output at different 

        -- Handle non-compatability.
        if v.name == v:symbol() then

            -- All these negation conditions are because (in general) these are
            -- cases where sysproto.h is not generated.
            if not v.type.NOARGS and
               not v.type.NOPROTO and
               not v.type.NODEF then

                if #v.args > 0 then
                    -- fh = sysarg
                    bio:print(string.format("struct %s {\n",
		    	        v.arg_alias))

		    	    for _, v in ipairs(v.args) do
		    		    if v.type == "int" and v.name == "_pad" and 
                           config.abiChanges("pair_64bit") then 
                            bio:print("#ifdef PAD64_REQUIRED\n")
                        end

		    		    bio:print(string.format(
                            "\tchar %s_l_[PADL_(%s)]; %s %s; char %s_r_[PADR_(%s)];\n",
                            v.name, v.type,
		    		        v.type, v.name,
		    		        v.name, v.type))

                        if v.type == "int" and v.name == "_pad" and
                           config.abiChanges("pair_64bit") then
                            bio:print("#endif\n")
                        end
		    		end

                    bio:print("};\n")

                else
                    -- fh = sysarg
                    bio:print(string.format(
		    	        "struct %s {\n\tsyscallarg_t dummy;\n};\n", v.alias))
                end

            -- Same thing, except no arguments.
            else if not v.type.NOPROTO and
                    not v.type.NODEF then

                local sys_prefix = "sys_"

                if v.name == "nosys" or v.name == "lkmnosys" or
                   v.name == "sysarch" or v.name:find("^freebsd") or
                   v.name:find("^linux") then
                    sys_prefix = ""
                end

                -- fh = sysdcl
                bio:print(string.format(
                    "%s\t%s%s(struct thread *, struct %s *);\n",
		            v.rettype, v.prefix, v.name, v.alias))
                -- fh = sysaue
		        bio:cache(string.format("#define\t%sAUE_%s\t%s\n",
		            config.syscallprefix, v.alias, v.audit), 1) 

            else
                -- all cases covered
            end
        -- noncompat done
        end
                
        -- Handle compatibility (everything >= FREEBSD3):
        elseif c >= 3 then

            if not v.type.NOPROTO and
               not v.type.NODEF and
               not v.type.NOARGS then

                if #v.args > 0 then
                    for _, v in ipairs(v.args) do
                        -- xxx out
		                bio:print(string.format(
		                    "\tchar %s_l_[PADL_(%s)]; %s %s; char %s_r_[PADR_(%s)];\n",
		                    v.name, v.type,
		                    v.type, v.name,
		                    v.name, v.type))
		             end
		             bio:print("};\n")
                else 
                     bio:print(string.format(
		                 "struct %s {\n\tsyscallarg_t dummy;\n};\n", v.arg_alias))
                end

            end

            if not v.type.NOPROTO and
               not v.type.NODEF then 
		        bio:print(string.format(
		            "%s\t%s%s(struct thread *, struct %s *);\n",
		            v.ret, v.prefix, v.name, v.arg_alias))
		        bio:cache(string.format(
		            "#define\t%sAUE_%s%s\t%s\n", config.syscallprefix,
		            v.prefix, v.name, v.audit), 1)
            end
        
        -- Handle obsolete, unimplemented, and reserved -- do nothing
        else
            -- do nothing
        end
    end
end

-- Entry

if #arg < 1 or #arg > 2 then
	error("usage: " .. arg[0] .. " syscall.master")
end

local sysfile, configfile = arg[1], arg[2]

config.merge(configfile)

-- The parsed syscall table
local tbl = FreeBSDSyscall:new{sysfile = sysfile, config = config}

genSysprotoH(tbl, config)
