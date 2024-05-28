--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2024 Tyler Baxter <agge@freebsd.org>
--

local config = require("config")

local scret = {}

scret.__index = scret

function scret:new(obj, line)
	obj = obj or { }
	setmetatable(obj, self)
	self.__index = self

	self.scret = line

	return obj
end

return scret
