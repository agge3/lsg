--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2024 Tyler Baxter <agge@freebsd.org>
--

local config = require("config")
local util = require("util")

local scret = {}

scret.__index = scret

function scret:init()
    self.line = util.split(self.line, "%S+")
    if #self.line ~= 2 then
        util.abort(1, "Malformed line " .. line)
    end
end

function scret:process()
    --[[ NOTE: Old script for reference:
    -- Don't clobber rettype set in the alt information
	if rettype == nil then
		rettype = "int"
	end
	-- Peel off the return type
	syscallret = line:match("([^%s]+)%s")
	line = line:match("[^%s]+%s(.+)")
	-- Pointer incoming
	if line:sub(1,1) == "*" then
		syscallret = syscallret .. " "
	end
	while line:sub(1,1) == "*" do
		line = line:sub(2)
		syscallret = syscallret .. " "
    ]]
end   

function scret:add()
    self.scret = self.line[1]
    return self.scret
end

function scret:new(obj, line)
	obj = obj or { }
	setmetatable(obj, self)
	self.__index = self

    self.line = line
	self.scret = ""

    obj:init()

	return obj
end

return scret
