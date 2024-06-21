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

local fh = "/dev/null" -- xxx temporary

local cfg = {
    syscallprefix = "SYS_" -- xxx this will be needed here
}

-- xxx this likely does not to be a data structure, but don't have a final 
-- decision on it
local noncompat = util.set {
    "STD",
    "NODEF", 
    "NOARGS", 
    "NOPROTO",
    "NOSTD",
}

local function genSysprotoH(tbl, cfg)
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
        if v.type.STD or
           v.type.NODEF or
           v.type.NOARGS or
           v.type.NOPROTO or
           v.type.NOSTD then
        -- xxx do nothing for now, handle noncompat
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

local cfg_mod = { }

config.mergeGlobal(configfile, cfg, cfg_mod)

-- The parsed syscall table
local tbl = FreeBSDSyscall:new{sysfile = sysfile, config = cfg}

genSysprotoH(tbl, cfg)
