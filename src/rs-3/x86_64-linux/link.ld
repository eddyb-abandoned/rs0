ENTRY(start)
SECTIONS {
    . = 0x400000 + SIZEOF_HEADERS;
    .text : { *(.text) }

    vm.data.start = .;
    vm.data : { *(vm.data) }
    vm.data.end = .;

    vm.code.start = .;
    vm.code : { *(vm.code) }
    vm.code.end = .;
}
