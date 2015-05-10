ENTRY(vm.start)
SECTIONS {
    . = 0x00001000 + SIZEOF_HEADERS;
    vm.native : { *(vm.native) }

    . = 0x00002000;
    vm.code.start = .;
    vm.code : { *(vm.code) }
    vm.code.end = .;

    vm.const.start = .;
    vm.const : { *(vm.const) }
    vm.const.end = .;

    . = 0x10000000;
    vm.arena.start = .;
    vm.arena :{ . = vm.arena.end - vm.arena.start; }
    vm.arena.end = 0xfff00000;

    . += 0x1000; /* Data stack guard page. */
    vm.stack.start = .;
    vm.stack :{ . = vm.stack.end - vm.stack.start; }
    vm.stack.end = 0xfffff000;
}
