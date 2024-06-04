--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2024 Tyler Baxter <agge@FreeBSD.org>
--

local scproto = {}

scarg.__index = scarg

function scproto:new(obj, line)
	obj = obj or { }
	setmetatable(obj, self)
	self.__index = self

	self.scproto = line

	return obj
end

return scproto
