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
require("test/dump")

-- Globals

local fh = "/dev/null"

local sysproto = "" .. ".h"
local sysproto_h = "" .. "_SYSPROTO_H_"


local function lookupCompatFlag(compat_options, compatlevel)
    for _, v in pairs(compat_options) do
        if v.compatlevel == compatlevel then
            return v.flag
        end
    end
    return nil
end

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

    -- Make a local copy of global compat options, write lines are going to be 
    -- stored in it. There's a lot of specific compat handling for sysproto.h
    local compat_options = config.compat_options

    -- Write out all the compat directives from compat_options
    -- NOTE: Linux won't have any, so it's skipped as expected.
    for _, v in pairs(config.compat_options) do
        -- 
        -- NOTE: Storing each compat entry requires storing multiple levels of 
        -- file generation; compat entries are given ranges of 10 instead to 
        -- cope with this.
        -- EXAMPLE: 13 is indexed as 130, 131 is the second generation level of 
        -- 13
        --
        -- Tag an extra newline to the end, so it doesn't have to be worried 
        -- about later.
        bio:store(string.format("\n#ifdef %s\n\n", v.definition), v.compatlevel * 10)
        print("First loop: " .. v.compatlevel)
	end

    for k, v in pairs(s) do
        local c = v:compat_level()
        if v.num > max then
            max = v.num
        end

        -- Audit defines are stored at an arbitrarily large number so that 
        -- they're always at the last storage level; to allow compat entries to 
        -- be indexed more intuitively (by their compat level).
        local audit_idx = 0xffffffff -- this should do

        -- Handle non-compatability.
        if v.name == v:symbol() then

            -- All these negation conditions are because (in general) these are
            -- cases where sysproto.h is not generated.
            if not v.type.NOARGS and
               not v.type.NOPROTO and
               not v.type.NODEF then

                if v.args ~= nil then
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
            elseif not v.type.NOPROTO and
                    not v.type.NODEF then

                local sys_prefix = "sys_"

                if v.name == "nosys" or v.name == "lkmnosys" or
                   v.name == "sysarch" or v.name:find("^freebsd") or
                   v.name:find("^linux") then
                    sys_prefix = ""
                end

                bio:store(string.format(
                    "%s\t%s%s(struct thread *, struct %s *);\n",
		            v.rettype, v.prefix, v.name, v.alias), 1)

                -- Audit defines are stored at an arbitrarily large number so 
                -- that they're always at the end; to allow compat entries to 
                -- just be indexed by their compat level.
		        bio:store(string.format("#define\t%sAUE_%s\t%s\n",
		            config.syscallprefix, v.alias, v.audit), audit_idx) 

            -- Handle reached end of native.
            elseif max >= v.num then
                -- nothing for now
            else
                -- all cases covered, do nothing
            end
        -- noncompat done
                
        --
        -- Handle compatibility (everything >= FREEBSD3)
        -- Because of the way sysproto.h is printed, lines are stored by their 
        -- compat level, then written in the expected order later.
        --
        -- NOTE: Storing each compat entry requires storing multiple levels of 
        -- file generation; compat entries are given ranges of 10 instead to 
        -- cope with this.
        -- EXAMPLE: 13 is indexed as 130, 131 is the second generation level of 
        -- 13
        -- 
        elseif c >= 3 then
            local idx = c * 10
            --print(idx)
            --print(idx)
            --print(idx)
            --print(idx)
            --print(idx)
            --print(idx)
            if not v.type.NOPROTO and
               not v.type.NODEF and
               not v.type.NOARGS then
                if v.args ~= nil then
                    bio:store(string.format("struct %s {\n", v.arg_alias), idx)
                    for _, arg in ipairs(v.args) do
		                bio:store(string.format(
		                    "\tchar %s_l_[PADL_(%s)]; %s %s; char %s_r_[PADR_(%s)];\n",
		                    arg.name, arg.type,
		                    arg.type, arg.name,
		                    arg.name, arg.type), idx)
		             end
		             bio:store("};\n", idx)
                else 
                     bio:store(string.format(
		                 "struct %s {\n\tsyscallarg_t dummy;\n};\n", v.arg_alias), idx)
                end
            end

            if not v.type.NOPROTO and
               not v.type.NODEF then 
		        bio:store(string.format(
		            "%s\t%s%s(struct thread *, struct %s *);\n",
		            v.rettype, v.prefix, v:symbol(), v.arg_alias), idx + 1)
		        bio:store(string.format(
		            "#define\t%sAUE_%s%s\t%s\n", config.syscallprefix,
		            v.prefix, v:symbol(), v.audit), audit_idx)
            end
        
        -- Handle obsolete, unimplemented, and reserved -- do nothing
        else
            -- do nothing
        end
    end

    -- Append #endif to each compat option.
    for _, v in pairs(config.compat_options) do
        -- If compat entries are indexed by 10s, then 9 will always be the end 
        -- of that compat entry.
        local end_idx = (v.compatlevel * 10) + 9
        bio:store(string.format("\n#endif /* %s */\n", v.definition), end_idx)
	end

    if bio.storage_levels ~= nil then
        bio:writeStorage()
    end

end

-- Entry

if #arg < 1 or #arg > 2 then
	error("usage: " .. arg[0] .. " syscall.master")
end

local sysfile, configfile = arg[1], arg[2]

config.merge(configfile)
config.mergeCompat()
config.mergeCapability()

-- The parsed syscall table
local tbl = FreeBSDSyscall:new{sysfile = sysfile, config = config}

genSysprotoH(tbl, config)
