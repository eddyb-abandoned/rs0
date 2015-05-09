OUTPUT_FORMAT("elf64-x86-64", "elf64-x86-64", "elf64-x86-64")
OUTPUT_ARCH(i386:x86-64)
ENTRY(vm.start)
SECTIONS {
    . = 0x00001000 + SIZEOF_HEADERS;
    vm.native : { *(vm.native) }

    . = 0x00002000;
    vm.code : { *(vm.code) }

    . = 0xfff01000;
    vm.stack :{ *(vm.stack) }
}
