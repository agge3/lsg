--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2024 Tyler Baxter <agge@freebsd.org>
--

-- Derived in large part from makesyscalls.lua:
--
-- SPDX-License-Identifier: BSD-2-Clause-FreeBSD
--
-- Copyright (c) 2019 Kyle Evans <kevans@FreeBSD.org>

local config = require("config")
local util = require("util")

local scret = {}

scret.__index = scret

-- Default initialization procedures.
function scret:init()
    -- Don't clobber rettype set in the alt information
    if self.scret == nil then
        self.scret = "int"
    end
end

-- Process the return type.
function scret:process()
	-- Pointer incoming
	if self.scret:sub(1,1) == "*" then
		self.scret = self.scret .. " "
	end
	while self.scret:sub(1,1) == "*" do
		line = line:sub(2)
		self.scret = self.scret .. " "
    end
end   

-- Handling has been done. To add the return type to the syscall object. 
function scret:add()
    self:process()
    return self.scret
end

-- Specialized class for handling the return type of a system call during 
-- parsing.
-- MORE can LIKELY be done here.
function scret:new(obj, ret)
	obj = obj or { }
	setmetatable(obj, self)
	self.__index = self

    self.scret = ret

    self:init()

	return obj
end

return scret
