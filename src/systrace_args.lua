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
    ptr_intptr_t_cast = "intptr_t"
}

local fh = "/dev/null" -- xxx temporary

local function gen_systrace_args(tbl, cfg)
    local bio = bsdio:new({ }, fh) 

    bio:generated([[
        System call argument to DTrace register array converstion.
        This file is part of the DTrace syscall provider.
    ]])

    bio:write(string.format([[
static void
systrace_args(int sysnum, void *params, uint64_t *uarg, int *n_args)
{
	int64_t *iarg = (int64_t *)uarg;
	int a = 0;
	switch (sysnum) {
]], bio:tag))

    bio:pad64(config.abi_changes("pair_64bit")) 

end

-- OLD SCRIPT:
-- noncompat
	write_line("systrace", string.format([[
	/* %s */
	case %d: {
]], funcname, sysnum))
	write_line("systracetmp", string.format([[
	/* %s */
	case %d:
]], funcname, sysnum))
	write_line("systraceret", string.format([[
	/* %s */
	case %d:
]], funcname, sysnum))

	if #funcargs > 0 and flags & known_flags.SYSMUX == 0 then
		write_line("systracetmp", "\t\tswitch (ndx) {\n")
		write_line("systrace", string.format(
		    "\t\tstruct %s *p = params;\n", argalias))


		local argtype, argname, desc, padding
		padding = ""
		for idx, arg in ipairs(funcargs) do
			argtype = arg.type
			argname = arg.name

			argtype = trim(argtype:gsub("__restrict$", ""), nil)
			if argtype == "int" and argname == "_pad" and abi_changes("pair_64bit") then
				write_line("systracetmp", "#ifdef PAD64_REQUIRED\n")
			end
			-- Pointer arg?
			if argtype:find("*") then
				desc = "userland " .. argtype
			else
				desc = argtype;
			end
			write_line("systracetmp", string.format(
			    "\t\tcase %d%s:\n\t\t\tp = \"%s\";\n\t\t\tbreak;\n",
			    idx - 1, padding, desc))
			if argtype == "int" and argname == "_pad" and abi_changes("pair_64bit") then
				padding = " - _P_"
				write_line("systracetmp", "#define _P_ 0\n#else\n#define _P_ 1\n#endif\n")
			end

			if isptrtype(argtype) then
				write_line("systrace", string.format(
				    "\t\tuarg[a++] = (%s)p->%s; /* %s */\n",
				    config.ptr_intptr_t_cast,
				    argname, argtype))
			elseif argtype == "union l_semun" then
				write_line("systrace", string.format(
				    "\t\tuarg[a++] = p->%s.buf; /* %s */\n",
				    argname, argtype))
			elseif argtype:sub(1,1) == "u" or argtype == "size_t" then
				write_line("systrace", string.format(
				    "\t\tuarg[a++] = p->%s; /* %s */\n",
				    argname, argtype))
			else
				if argtype == "int" and argname == "_pad" and abi_changes("pair_64bit") then
					write_line("systrace", "#ifdef PAD64_REQUIRED\n")
				end
				write_line("systrace", string.format(
				    "\t\tiarg[a++] = p->%s; /* %s */\n",
				    argname, argtype))
				if argtype == "int" and argname == "_pad" and abi_changes("pair_64bit") then
					write_line("systrace", "#endif\n")
				end
			end
		end

		write_line("systracetmp",
		    "\t\tdefault:\n\t\t\tbreak;\n\t\t};\n")
		if padding ~= "" then
			write_line("systracetmp", "#undef _P_\n\n")
		end

		write_line("systraceret", string.format([[
		if (ndx == 0 || ndx == 1)
			p = "%s";
		break;
]], syscallret))
	end
	local n_args = #funcargs
	if flags & known_flags.SYSMUX ~= 0 then
		n_args = 0
	end
	write_line("systrace", string.format(
	    "\t\t*n_args = %d;\n\t\tbreak;\n\t}\n", n_args))
	write_line("systracetmp", "\t\tbreak;\n")

-- obsol
-- do nothing

-- compat
-- trace what out is

-- unimpl
-- do nothing

-- reserved
-- calls unimpl



write_line("systracetmp", [[static void
systrace_entry_setargdesc(int sysnum, int ndx, char *desc, size_t descsz)
{
	const char *p = NULL;
	switch (sysnum) {
]])

write_line("systraceret", [[static void
systrace_return_setargdesc(int sysnum, int ndx, char *desc, size_t descsz)
{
	const char *p = NULL;
	switch (sysnum) {
]])

write_line("systrace", [[
	default:
		*n_args = 0;
		break;
	};
}
]])

write_line("systracetmp", [[
	default:
		break;
	};
	if (p != NULL)
		strlcpy(desc, p, descsz);
}
]])

write_line("systraceret", [[
	default:
		break;
	};
	if (p != NULL)
		strlcpy(desc, p, descsz);
}
]])

write_line("systrace", read_file("systracetmp"))
write_line("systrace", read_file("systraceret"))
