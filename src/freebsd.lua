#!/usr/libexec/flua
--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2023 Warner Losh <imp@bsdimp.com>
-- Copyright (c) 2024 Tyler Baxter <agge@FreeBSD.org>
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
-- available in ports.  Currently, this script is compatible with lua from ports
-- along with the compatible luafilesystem and lua-posix modules.

-- The FreeBSD syscall generator
local FreeBSDSyscall = require("freebsd-syscall")

local config = require("config")                -- common config file management
local syscalls = require("syscalls")
local syscall_h = require("syscall_h")
local syscall_mk = require("syscall_mk")
local init_sysent = require("init_sysent")
local systrace_args = require("systrace_args")
local sysproto_h = require("sysproto_h")

-- Entry
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

-- Output files
--syscalls.file = config.sysnames
--syscall_h.file = config.syshdr
--syscall_mk.file = config.sysmk
--init_sysent.file = config.syssw
--systrace_args.file = config.systrace
--sysproto_h.file = config.sysproto

-- Test output files
syscalls.file = "test/syscalls.c"
syscall_h.file = "test/syscall.h"
syscall_mk.file = "test/syscall.mk"
init_sysent.file = "test/init_sysent.c"
systrace_args.file = "test/systrace_args.c"
sysproto_h.file = "test/sysproto.h"

syscalls.generate(tbl, config, syscalls.file)
syscall_h.generate(tbl, config, syscall_h.file)
syscall_mk.generate(tbl, config, syscall_mk.file)
init_sysent.generate(tbl, config, init_sysent.file)
systrace_args.generate(tbl, config, systrace_args.file)
sysproto_h.generate(tbl, config, sysproto_h.file)
