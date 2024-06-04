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

local cfg = {
    ptr_intptr_t_cast = "intptr_t"
}

local function gen_systrace_args(tbl, cfg)
    -- xxx not going to have correct output
    util.generated_tag("System call argument to DTrace register array converstion")
end
