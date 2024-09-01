#!/usr/libexec/flua
--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2024 Tyler Baxter <agge@FreeBSD.org>
-- Copyright (c) 2023 Warner Losh <imp@bsdimp.com>
-- Copyright (c) 2019 Kyle Evans <kevans@FreeBSD.org>
--

-- Setup to be a module, or ran as its own script.
local init_sysent = {}
local script = not pcall(debug.getlocal, 4, 1) -- TRUE if script.
if script then
    -- Add library root to the package path.
    local path = arg[0]:gsub("/[^/]+.lua$", "")
    package.path = package.path .. ";" .. path .. "/../?.lua"
end

local FreeBSDSyscall = require("core.freebsd-syscall")
local util = require("tools.util")
local generator = require("tools.generator")

-- File has not been decided yet; config will decide file. Default defined as
-- null
init_sysent.file = "/dev/null"

-- Should be the same as makesyscalls.lua generates, except that we don't bother
-- to align the system call stuff... it's badly broken anyway and looks like crap
-- so we're declaring that a bug and removing all that crazy book-keeping to.
-- If we need to do it, and I hope we don't, I'll just create a string and do
-- #str to figure out how many tabs to add
function init_sysent.generate(tbl, config, fh)
    -- Grab the master system calls table.
    local s = tbl.syscalls

    -- Bind the generator to the parameter file.
    local gen = generator:new({}, fh)

    -- Write the generated preamble.
    gen:preamble("System call switch table.")

	gen:write(tbl.includes)

    -- Newline before and after this line.
	gen:write("\n#define AS(name) (sizeof(struct name) / sizeof(syscallarg_t))\n")

    -- Write out all the compat directives from compat_options.
    for _, v in pairs(config.compat_options) do
        gen:write(string.format([[

#ifdef %s
#define %s(n, name) .sy_narg = n, .sy_call = (sy_call_t *)__CONCAT(%s, name)
#else
#define %s(n, name) .sy_narg = 0, .sy_call = (sy_call_t *)nosys
#endif
]], v.definition, v.flag:lower(), v.prefix, v.flag:lower()))
	end
    -- Add a newline only if there were compat_options.
    if config.compat_options ~= nil then
        gen:write("\n")
    end

    gen:write(string.format([[
/* The casts are bogus but will do for now. */
struct sysent %s[] = {
]], config.switchname))

    for _, v in pairs(s) do
        local c = v:compatLevel()
        local argssize = util.processArgsize(v)
        -- Comment is the function alias by default, but may change based on the
        -- type of system call.
        local comment = v.alias
        -- Creating a string first, to allow lengthing the string to align 
		-- comments.
        local str

        -- Handle non-compat:
        if v:native() then
            str = string.format(
                "\t{ .sy_narg = %s, .sy_call = (sy_call_t *)",
                argssize)
            -- Handle SYSMUX flag:
            if v.type.SYSMUX then
                str = str .. string.format(
	                "nosys, .sy_auevent = AUE_NULL, " ..
	                ".sy_flags = %s, .sy_thrcnt = SY_THR_STATIC },",
	                v.cap)
            -- Handle NOSTD flag:
            elseif v.type.NOSTD then
                str = str .. string.format(
                    "lkmressys, .sy_auevent = AUE_NULL, " ..
                    ".sy_flags = %s, .sy_thrcnt = SY_THR_ABSENT },",
                    v.cap)
            -- Handle rest of non-compat:
			else
	            if v.name == "nosys" or v.name == "lkmnosys" or
                   v.name == "sysarch" or v.name:find("^freebsd") or
                   v.name:find("^linux") then
                    str = str .. string.format(
                        "%s, .sy_auevent = %s, .sy_flags = %s, " ..
                        ".sy_thrcnt = %s },",
                        v:symbol(), v.audit, v.cap, v.thr)
                else
                    str = str .. string.format(
                        "sys_%s, .sy_auevent = %s, .sy_flags = %s, " ..
                        ".sy_thrcnt = %s },",
                        v:symbol(), v.audit, v.cap, v.thr)
                end
			end

        -- Handle compat (everything >= FREEBSD3):
        elseif c >= 3 then
            -- Lookup the info for this specific compat option.
            local flag, descr
            for _, opt in pairs(config.compat_options) do
                if opt.compatlevel == c then
                    flag = opt.flag
                    flag = flag:lower()
                    descr = opt.descr
                    break
                end
            end

            if v.type.NOSTD then
                str = string.format(
                    "\t{ .sy_narg = %s, .sy_call = (sy_call_t *)%s, " ..
                    ".sy_auevent = %s, .sy_flags = 0, " ..
                    ".sy_thrcnt = SY_THR_ABSENT },",
                    "0", "lkmressys", "AUE_NULL")
	        else
                str = string.format(
                    "\t{ %s(%s,%s), .sy_auevent = %s, .sy_flags = %s, " ..
                    ".sy_thrcnt = %s },",
                    flag, argssize, v.name, v.audit, v.cap, v.thr)
            end
            comment = descr .. " " .. v.alias

        -- Handle obsolete:
        elseif v.type.OBSOL then
	        str = "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
	            ".sy_auevent = AUE_NULL, .sy_flags = 0, " ..
                ".sy_thrcnt = SY_THR_ABSENT },"
            comment = "obsolete " .. v.alias

        -- Handle unimplemented:
        elseif v.type.UNIMPL then
		    str = "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
		        ".sy_auevent = AUE_NULL, .sy_flags = 0, " ..
		        ".sy_thrcnt = SY_THR_ABSENT },"
            -- UNIMPL comment is not different in sysent.

        -- Handle reserved:
        elseif v.type.RESERVED then
            str = "\t{ .sy_narg = 0, .sy_call = (sy_call_t *)nosys, " ..
				".sy_auevent = AUE_NULL, .sy_flags = 0, " ..
		        ".sy_thrcnt = SY_THR_ABSENT },"
            comment = "reserved for local use"
        end

		-- If string is NIL, we don't write.
		if str ~= nil then
			-- Append the comment. Comments are not aligned; they're just tabbed
			-- from the end.
			str = str .. string.format("\t/* %d = %s */\n", v.num, comment)
        	-- Finally, write out the string we've built up.
            gen:write(str)
        end
    end

    -- End
    gen:write("};\n")
end

-- Entry of script:
if script then
    local config = require("config")

    if #arg < 1 or #arg > 2 then
        error("usage: " .. arg[0] .. " syscall.master")
    end

    local sysfile, configfile = arg[1], arg[2]

    config.merge(configfile)
    config.mergeCompat()
    config.mergeCapability()

    -- The parsed syscall table
    local tbl = FreeBSDSyscall:new{sysfile = sysfile, config = config}

    init_sysent.file = config.syssw -- change file here
    init_sysent.generate(tbl, config, init_sysent.file)
end

-- Return the module
return init_sysent
