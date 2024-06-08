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

util = require("util")

local bsdio = {}

bsdio.__index = bsdio

function bsdio:write(line)
	assert(self.fh:write(line))
end

function bsdio:pad64(bool)
    if bool then
	    self:write(string.format([[
#if !defined(PAD64_REQUIRED) && !defined(__amd64__)
#define PAD64_REQUIRED
#endif
]]))
    end
end

-- Writes the generated tag.
-- @param str
-- The title of the file.
-- @param [comment]
-- Default comment is C comments. Optional to change comment (e.g., to sh 
-- comments). Will still follow C-style indentation. @see style(9)
-- @note Handles multi-line titles, deliminated by newlines.
function bsdio:generated_tag(str, comment)
    local comment_start = comment or "/*"
    local comment_middle = comment or "*"
    local comment_end = comment or "*/"
    local tag = "@" .. "generated"

    -- Don't enter loop if it's the simple case.
    if str:find("\n") == nil then
        self:write(string.format([[%s
 %s %s
 %s
 %s DO NOT EDIT-- this file is automatically %s.
 %s
]], comment_start, comment_middle, str, comment_middle, comment_middle, tag, 
            comment_end)) 

    else
        self:write(string.format([[%s]], comment_start))
        for line in str:gmatch("[^\n]*") do
            if line ~= nil then
                self:write(string.format([[
 %s %s]], comment_middle, line))
            end
        end
        self:write(string.format([[ %s
 %s DO NOT EDIT-- this file is automatically %s
 %s
]], comment_middle, comment_middle, tag, comment_end))
    end
end

function bsdio:old(compat_level)
   	--elseif c >= 0 then
	--	local s
	--	if c == 0 then
	--		s = "obsolete"
	--	elseif c == 3 then
	--		s = "old"
	--	else
	--		s = "freebsd" .. c
	--	end 
end

function bsdio:new(obj, fh)
    obj = obj or { }
    setmetatable(obj, self)
    self.__index == self

    self.bsdio = fh

    if self.fh == nil then
        util.abort("Not found: " .. self.fh)
    end

    return obj
end

return bsdio
