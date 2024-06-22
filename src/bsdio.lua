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

-- Simple wrapper for lua IO best practice. For a simpler write call.
function bsdio:write(line)
	assert(self.fh:write(line))
end

-- xxx just to print output for now, and still use class
function bsdio:print(line)
    print(line)
end

--
-- An IO macro for the PAD64 preprocessor directive. 
-- PARAM: bool, TRUE to pad
-- USAGE: Pass the result of ABI checks and padding will be done if necessary.
--
function bsdio:pad64(bool)
    if bool then
	    self:write(string.format([[
#if !defined(PAD64_REQUIRED) && !defined(__amd64__)
#define PAD64_REQUIRED
#endif
]]))
    end
end

-- Returns the generated tag. Useful if only the tag is needed.
function bsdio:tag()
    return self.tag
end

--
-- Writes the generated tag. Default comment is C comments. 
--
-- PARAM: String str, the title of the file
--
-- PARAM: String comment, nil or optional to change comment (e.g., to sh comments).
-- Will still follow C-style indentation.
-- SEE: style(9)
--
-- NOTE: Handles multi-line titles, deliminated by newlines.
--
function bsdio:generated(str, comment)
    local comment_start = comment or "/*"
    local comment_middle = comment or "*"
    local comment_end = comment or "*/"

    -- Don't enter loop if it's the simple case.
    if str:find("\n") == nil then
        self:write(string.format([[%s
 %s %s
 %s
 %s DO NOT EDIT-- this file is automatically %s.
 %s
]], comment_start, comment_middle, str, comment_middle, comment_middle, 
            self.tag, comment_end)) 

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
]], comment_middle, comment_middle, self.tag, comment_end))
    end
end

-- xxx just a thought, we'll see if there's anything that can done in this 
-- regard
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

-- File is part of bsdio's identity. Different objects with different identities 
-- (files) can be behave differently in a module.
function bsdio:new(obj, fh)
    obj = obj or { }
    setmetatable(obj, self)
    self.__index == self

    self.bsdio = fh
    self.tag = "@" .. "generated" 

    if self.bsdio == nil then
        util.abort("Not found: " .. self.bsdio)
    end

    return obj
end

return bsdio
