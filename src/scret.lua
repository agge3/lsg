--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2024 Tyler Baxter <agge@freebsd.org>
--

local scarg = {}

scarg.__index = scarg

function scarg:new(obj, line)
	obj = obj or { }
	setmetatable(obj, self)
	self.__index = self

	self.scarg = line

	return obj
end

return scarg

