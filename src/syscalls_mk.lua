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

-- Globals

local sysmk = "/dev/null"

local fh = "/dev/null" -- xxx temporary

-- Default configuration; any of these may get replaced by a configuration file
-- optionally specified. A lot of these are passed into the fbsd_sys parser and
-- the bsd_user code generator A bit tricky because a lot of the inherited code
-- has a global config table that it referrs to deep in the call tree... need to
-- make sure that all that code is converted to using one local to the object.
local cfg = {

}

-- Libc has all the STD, NOSTD and SYSMUX system calls in it, as well as
-- replaced system calls dating back to FreeBSD 7. We are lucky that the
-- system call filename is just the base symbol name for it.
local function genSyscallsMk(tbl, config)
    -- Grab the master syscalls table.
	local s = tbl.syscalls

    -- Init the bsdio object, has macros and procedures for LSG specific io.
    local bio = bsdio:new({ }, fh) 

    -- Write the generated tag.
    --bio:generated()

	for k, v in pairs(s) do
		if  v.type.STD or
			v.type.NOSTD or
			v.type.SYSMUX or
			v:compat_level() >= 7
		then
			print(string.format("%s.o", v:symbol()))
		end
	end
end

-- Entry

if #arg < 1 or #arg > 2 then
	error("usage: " .. arg[0] .. " syscall.master")
end

local sysfile, configfile = arg[1], arg[2]

local cfg_mod = {}

config.mergeGlobal(configfile, cfg, cfg_mod)

-- The parsed syscall table
local tbl = FreeBSDSyscall:new{sysfile = sysfile, config = cfg}

genSyscallsMk(tbl, config)
