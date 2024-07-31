# Lua Syscall Generator
Google Summer of Code 2024 (GSoC 2024) project *Refactor Syscall Creation Script*, now formally called *Lua Syscall Generator (LSG)*, is a refactor of FreeBSD's <code>makesyscalls.lua</code> as a library.
## Usage
### To generate and perform as expected to <code>makesyscalls.lua</code>:
<code>lsg/src $ /usr/libexec/flua freebsd.lua ../sys/kern/syscalls.master</code><br>
*Optionally specified configuration file or a different ABI <code>syscalls.master</code> may be provided.*
### For modules, to generate the specific file associated with the module and no other files:
<code>lsg/src $ /usr/libexec/flua module-name ../sys/kern/syscalls.master</code><br>
*Optionally specified configuration file or a different ABI <code>syscalls.master</code> may be provided.*
#### Modules
<code>syscalls.lua, syscall_h.lua, syscall_mk.lua, init_sysent.lua, systrace_args.lua, sysproto_h.lua</code>
### Notes
<code>freebsd.lua</code> is currently setup to produce all generated files in <code>src/test</code><br>
To test file generation, *use <code>freebsd.lua</code>*<br><br>
For modules, generated file paths are currently setup as they are specified in the optionally provided configuration file (or default configuration, if not provided).<br>
WARNING: With the current directory setup, files are likely to be produced in unexpected locations.
## Deliverables
1. System call creation will work as before
2. <code>makesyscalls.lua</code> is refactored into core, modules, and classes
3. System call creation library is easily extensible (It should provide a basis for future system call creation scripts)
4. Well-documented (e.g., "bsd_foo will be generated", how to opt-out of complex generation, etc.)
## Outcomes
1. To meet the deliverable that system call creation will work as before:<br>
<code>lsg/src $ /usr/libexec/flua freebsd.lua ../sys/kern/syscalls.master</code><br>
2. To meet the deliverable that <code>makesyscalls.lua</code> is refactored into core, modules, and classes:<br> 
<code>lsg/src $ /usr/libexec/flua module-name ../sys/kern/syscalls.master</code><br>
3. To accomplish the deliverable of a system call creation library that is easily extensible:<br>
An entirely different design of <code>makesyscalls.lua</code>, including:<br>
* No bitmasks, bit flags, or bitwise operations are done. Types are declarative and match the readability of <code>syscalls.master</code> in the form of <code>syscall.type.STD</code>
* The processing of arguments and return type is decoupled into classes <code>scarg</code> and <code>scret</code>, respectively.
* Common procedures are made globally accessible and reusable in <code>util.lua</code> and <code>config.lua</code>
* <code>class bsdio</code> is an IO class that simplifies the calls of best-practice Lua IO calls, carries internal state that can be changed dynamically, and provides an interface for common IO macros.
* Instead of writing to temporary files and "stitching" them together, <code>class bsdio</code> allows caching of different stages of generation in the form of "storage levels". Lines can stored in their respective storage level, all in one write pass, and unrolled accordingly.
* Each module has a much different and more readable procedure of generating files, decoupled from the rest. This allows new contributors to approach the library easier and experienced users to extend it easier.
4. To accomplish the deliverable of being well-documented:<br>
Thorough explanation of procedures and semantics are commented throughout the library. Along with function explanations, any unclarity from <code>makesyscalls.lua</code> is now explained and commented. Usage of the library is documented in "Usage"
### Final Outcome:
Overall, the project was very successful. The goal of decoupling <code>makesyscalls.lua</code> was accomplished and the library is much clearer, easier to work with, and easier to make changes to.
## Todo
* Different ABI targets have not be thoroughly tested.
* Due to the sheer output of lines of LSG's file generation it’s possible native (amd64) is not 100% correct either. Possibly a tool can be engineered to confirm the output; however, that was not within scope of the original project.
* Being the goal is deliver identical file generation to <code>makesyscalls.lua</code>, after final review these issues will be addressed until successful upstream integration can be accomplished.
