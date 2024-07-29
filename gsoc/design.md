# MAJOR GOAL:
have most of this stuff as uncoupled as possible. entire reason for doing this
is so that it's easy to extend, and also easy for those unfamilar with the script
to jump in and extend.

# core
creates FreeBSDSyscall object, which should instantiate itself with everything
it needs to
then, just run down the modules
    (e.g., like gen_syscalls_h)
and achieve the same output
    init_sysent.lua
    syscall_h.lua
    syscalls.lua
    syscalls_mk.lua
    systrace_args.lua

### ALSO needs to:
have a method of opting out of complex file generation.
shouldn't really be a hastle though.
probably do what it needs to do by default, and pass inclusion/exclusion args
    e.g., ./makesyscalls --include=init_sysent,syscall  # only does init_sysent.h and syscall.c
          ./makesyscalls --exclude=systrace_args        # does everything except systrace_args.h
    also a great place to provide man page and further online documentation

# syscall interfaces
## freebsd-syscall.lua
packages each syscall into a table of freebsd syscalls
### already implemented:
parse_sysfile()
    * parses sys file and assigns proper includes and defines
inits itself to have proper includes and defines

## scarg.lua
packages arg info
__NOTE:__ although it seems nice to package it into syscall.lua, this is a 
complicated procedure. like the idea of it being its own object.

## scret.lua
packages ret info

## syscall.lua

### this note mainly needs to be addressed:
-- XXX need to sort out how to do compat stuff...
-- native is the only compat thing
-- Also need to figure out the different other things that 'filter' system calls
-- since the abi32 stuff does that.

### syscall:add()
let's have different state names:
    syscall:addparse

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
    util.write() OR just write.lua -- 5-6 different write procedures seems i
    like that can be generalized

# output file, module generation
__NOTE:__ Pretty much exactly like Warner's current, gen_syscall_h(tbl, cfg)
and gen_syscall_mk(tbl, cfg).
I like the idea of passing cfg like it's a context, so perhaps for the files 
needing additional data, just pin that in as a key in cfg.
like, abi_changes expands into all the abi_changes
OR package it into the syscall object 
## init_sysent.lua
## syscall_h.lua
## syscalls.lua
## syscalls_mk.lua
## systrace_args.lua
## sysproto_h.lua

# uncoupling original makesyscalls.awk
MAYBE: not going to need write_line() and write_line_pfile(), doing separate 
module handling, althought the err checking might be nice

## process_args()
isptrtype()
isptrarraytype()
is64bittype()
    these are only relevant to args, so can defintely just be part of scargs 
    procedures.
strip_arg_annotations()
    also relevant to only args.

## process_syscall_def
## handle_compat(), handle_noncompat(), handle_obsol(), handle_reserved()
all of the flags in this need to be available in config (some might), but it needs
to be referenced for auto-gen cases

### Meaning...
sysnum, thr_flag, flags, sysflags, rettype, auditev, funcname, funcalias, 
funcargs, argalias, syscallret

## abi_changes
this can go in config, will need it for quite a few cases in generating files.

## strip_abi_prefix()
only needed for capsicum? maybe have in util though, seems useful.

# Additional thoughts:
* Are there maybe areas where an additional class would be better?
* How much should be packaged in the syscall object, ret and args are already 
separate classes? (i.e., should there be a "processing class" and a 
"data storage class", would uncouple quite a bit)
* Inserting things in config, as opposed to having them carried in an objects state.
* How much of the write procedures should be reused, what can be reused, and if that
should be its own module/class.
