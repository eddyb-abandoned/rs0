ENTRY(vm.start)
PHDRS {
  native PT_LOAD FILEHDR PHDRS;
  rodata PT_LOAD;
  data PT_LOAD;
}
SECTIONS {
    . = 0x100001000 + SIZEOF_HEADERS;
    vm.native : { *(vm.native) } :native

    . = 0x100002000;
    vm.data.start = .;
    vm.data : { *(vm.data) } :data
    vm.data.end = .;

    /* The 0x1000's are stack guard pages. */
    vm.stack.start = 0x1fff00000 + 0x1000;
    vm.stack.end = 0x200000000 - 0x1000;
    vm.stack (vm.stack.start): {
        . = vm.stack.end - vm.stack.start;
        *(vm.stack)
    } :data

    . = 0x200000000;
    vm.code.start = .;
    vm.code : { *(vm.code) } :rodata
    vm.code.end = .;
}
