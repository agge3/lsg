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
    syscallprefix = "SYS_"
}

local function gen_sysproto_h(tbl, cfg)
    util.generated_tag("System call prototypes.")
end

-- noncompat
local nargflags = get_mask({"NOARGS", "NOPROTO", "NODEF"})
	if flags & nargflags == 0 then
	if #funcargs > 0 then
			write_line("sysarg", string.format("struct %s {\n",
			    argalias))
			for _, v in ipairs(funcargs) do
				local argname, argtype = v.name, v.type
				if argtype == "int" and argname == "_pad" and abi_changes("pair_64bit") then
					write_line("sysarg", "#ifdef PAD64_REQUIRED\n")
				end
				write_line("sysarg", string.format(
				    "\tchar %s_l_[PADL_(%s)]; %s %s; char %s_r_[PADR_(%s)];\n",
				    argname, argtype,
				    argtype, argname,
				    argname, argtype))
				if argtype == "int" and argname == "_pad" and abi_changes("pair_64bit") then
					write_line("sysarg", "#endif\n")
				end
			end
			write_line("sysarg", "};\n")
		else
			write_line("sysarg", string.format(
			    "struct %s {\n\tsyscallarg_t dummy;\n};\n", argalias))
		end
	end
	local protoflags = get_mask({"NOPROTO", "NODEF"})
	if flags & protoflags == 0 then
		local sys_prefix = "sys_"
		if funcname == "nosys" or funcname == "lkmnosys" or
		    funcname == "sysarch" or funcname:find("^freebsd") or
		    funcname:find("^linux") then
			sys_prefix = ""
		end
		write_line("sysdcl", string.format(
		    "%s\t%s%s(struct thread *, struct %s *);\n",
		    rettype, sys_prefix, funcname, argalias))
		write_line("sysaue", string.format("#define\t%sAUE_%s\t%s\n",
		    config.syscallprefix, funcalias, auditev))
	end

