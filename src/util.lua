--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2023 Warner Losh <imp@bsdimp.com>
--

-- Derived in large part from makesyscalls.lua:
--
-- SPDX-License-Identifier: BSD-2-Clause-FreeBSD
--
-- Copyright (c) 2019 Kyle Evans <kevans@FreeBSD.org>

local util = {}

function util.trim(s, char)
	if s == nil then
		return nil
	end
	if char == nil then
		char = "%s"
	end
	return s:gsub("^" .. char .. "+", ""):gsub(char .. "+$", "")
end

-- Returns a table (list) of strings
function util.split(s, re)
	local t = { }

	for v in s:gmatch(re) do
		table.insert(t, v)
	end
	return t
end

function util.abort(status, msg)
	assert(io.stderr:write(msg .. "\n"))
	-- cleanup
	os.exit(status)
end

function util.Set(t)
	local s = { }
	for _,v in pairs(t) do s[v] = true end
	return s
end

function util.SetFromString(str, re)
	local s = { }

	for v in str:gmatch(re) do
		s[v] = true
	end
	return s
end

-- Prints the generated tag.
-- @param str
-- The title of the file.
-- @param [comment]
-- Default comment is C comments. Optional to change comment (e.g., to sh 
-- comments). Will still follow C-style indentation. @see style(9)
-- @note Handles multi-line titles, deliminated by newlines.
function util.generated_tag(str, comment)
    local comment_start = comment or "/*"
    local comment_middle = comment or "*"
    local comment_end = comment or "*/"
    local tag = "@" .. "generated"

    -- Don't enter loop if it's the simple case.
    if str:find("\n") == nil then
        print(string.format([[%s
 %s %s
 %s
 %s DO NOT EDIT-- this file is automatically %s.
 %s
]], comment_start, comment_middle, str, comment_middle, comment_middle, tag, 
            comment_end)) 

    else
        print(string.format([[%s]], comment_start))
        for line in str:gmatch("[^\n]*") do
            if line ~= nil then
                print(string.format([[
 %s %s]], comment_middle, line))
            end
        end
        print(string.format([[ %s
 %s DO NOT EDIT-- this file is automatically %s
 %s
]], comment_middle, comment_middle, tag, comment_end))
    end
end

-- Checks for pointer types: '*', caddr_t, intptr_t.
-- @param type
-- The type to check.
-- @param [abi]
-- Optional ABI-specified intptr_t.
function util.isptrtype(type, abi)
    local default = "intptr_t" or abi
	return type:find("*") or type:find("caddr_t") or type:find(default)
end

function util.isptrarraytype(type)
	return type:find("[*][*]") or type:find("[*][ ]*const[ ]*[*]")
end

-- Find types that are always 64-bits wide.
function util.is64bittype(type)
	return type:find("^dev_t[ ]*$") or type:find("^id_t[ ]*$") 
        or type:find("^off_t[ ]*$")
end

function util.strip_abi_prefix(funcname, abiprefix)
	local stripped_name
	if funcname == nil then
		return nil
	end
	if abiprefix ~= "" and funcname:find("^" .. abiprefix) then
		stripped_name = funcname:gsub("^" .. abiprefix, "")
	else
		stripped_name = funcname
	end

	return stripped_name
end

return util
