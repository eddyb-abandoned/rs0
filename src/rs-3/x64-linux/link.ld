ENTRY(vm.start)
PHDRS {
  native PT_LOAD FILEHDR PHDRS;
  rodata PT_LOAD;
  data PT_LOAD;
}
SECTIONS {
    . = 0x00001000 + SIZEOF_HEADERS;
    vm.native : { *(vm.native) } :native

    . = 0x00002000;
    vm.code.start = .;
    vm.code : { *(vm.code) } :rodata
    vm.code.end = .;

    vm.const.start = .;
    vm.const : { *(vm.const) } :rodata
    vm.const.end = .;

    vm.arena.start = 0x10000000;
    vm.arena.end = 0xfff00000;
    vm.arena (vm.arena.start): {
        . = vm.arena.end - vm.arena.start;
        *(vm.arena)
    } :data

    /* The 0x1000's are stack guard pages. */
    vm.stack.start = vm.arena.end + 0x1000;
    vm.stack.end = 0x100000000 - 0x1000;
    vm.stack (vm.stack.start): {
        . = vm.stack.end - vm.stack.start;
        *(vm.stack)
    } :data
}
