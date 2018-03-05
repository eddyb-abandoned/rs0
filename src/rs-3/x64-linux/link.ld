ENTRY(start)
SECTIONS {
    .text : { *(.text) }

    vm.data.start = .;
    vm.data : { *(vm.data) }
    vm.data.end = .;

    vm.code.start = .;
    vm.code : { *(vm.code) }
    vm.code.end = .;
}
