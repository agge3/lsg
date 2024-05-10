# core
## freebsd.lua
### already implemented:
gen_syscalls_h(tbl, config)
    move to syscalls_h.lua
takes parse syscall table from freebsd-syscall.lua
### needs to:
create local freebsd-syscall object with parsed syscall
call...
    init_sysent.lua
    syscall_h.lua
    syscalls.lua
    syscalls_mk.lua
    systrace_args.lua
### ALSO needs to:
have a method of opting out of complex file generation.
shouldn't really be a hastle though.
probably do what it needs to do by default, and pass inclusion/exclusion args
    e.g., ./makesyscalls --modules=init_sysent,syscall  # only does init_sysent.h and syscall.c
          ./makesyscalls --exclude=systrace_args        # does everything except systrace_args.h
    also a great place to provide man page and further online documentation

# syscall interfaces
## freebsd-syscall.lua
packages generic syscall information into a freebsd syscall
__note:__ design syscall information in a way that's compat with other BSDs?
### already implemented:
parse_sysfile()
    * parses sys file and assigns proper includes and defines
inits itself to have proper includes and defines

## scarg.lua
packages arg info

## scret.lua
packages ret info

## syscall.lua
__question:__ is there a specific reason why scarg isn't just a method of 
syscall, like syscall:symbol() or syscall:compat_level(), or do you want 
entirely separate interfaces ((note-to-self: look into more!) and for what 
reason?, more extensible in the future?)

### syscall:add()
    polymorphic behavior, definitely think there should be state identifiers

### syscall:symbol()
OBSEL, RESERVED, UNIMPL (symbol name)

### syscall:compat_level()
-- Return the compatibility level for this system call
-- 0 is obsolete
-- < 0 is this isn't really a system call we care about
-- 3 is 4.3BSD in theory, but anything before FreeBSD 4
-- >= 4 FreeBSD version this system call was replaced with a new version

### break down syscall:add()
1. init()
2. parse fn name()
    rettype
3. eating args()
    args

# global namespace
## config.lua
misc config, config should be a declarative procedure
## util.lua
### MAYBE:
    util.write() OR just write.lua -- 5-6 different write procedures seems like that can be generalized

# output file, module generation
## init_sysent.lua
## syscall_h.lua
## syscalls.lua
## syscalls_mk.lua
## systrace_args.lua
## sysproto_h.lua

# uncoupling original makesyscalls.awk
MAYBE: not going to need write_line() and write_line_pfile(), doing separate 
module handling, althought the err checking might be nice

LOOK INTO: ptrtype, ptrarraytype, is64bittype
