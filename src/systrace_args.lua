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

local systrace = "" .. "_systrace_args.c"

local fh = "/dev/null" -- xxx temporary

local cfg = {
    ptr_intptr_t_cast = "intptr_t" -- xxx will be needed here
}

local cfg_mod = {

}

local function genSystraceArgs(tbl, cfg)
    -- Init the bsdio object, has macros and procedures for LSG specific io.
    local bio = bsdio:new({ }, fh) 

    -- generated() will be able to handle the newline here.
    -- NOTE: This results in a different output than makesyscalls.lua 
    bio:generated([[
        System call argument to DTrace register array converstion.
        This file is part of the DTrace syscall provider.
    ]])

    -- tag() will provide that generated tag if it is needed separate from 
    -- generated()
    bio:write(string.format([[
static void
systrace_args(int sysnum, void *params, uint64_t *uarg, int *n_args)
{
	int64_t *iarg = (int64_t *)uarg;
	int a = 0;
	switch (sysnum) {
]], bio:tag)) 

    -- pad64() is an io macro that will pad based on the result of 
    -- abi_changes().
    bio:pad64(config.abi_changes("pair_64bit")) 
end

-- Entry

if #arg < 1 or #arg > 2 then -- xxx subject to change
	error("usage: " .. arg[0] .. " syscall.master")
end

local sysfile, configfile = arg[1], arg[2]

config.mergeGlobal(fh, cfg, cfg_mod)

local cfg_mod = {}

-- The parsed syscall table
local tbl = FreeBSDSyscall:new{sysfile = sysfile, config = config}

genSystraceArgs(tbl, config)
