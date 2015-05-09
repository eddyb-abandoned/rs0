SECTION vm.code

%macro LIT 1
    db 2
    dd %1
%endmacro

%macro CALL 1
    LIT %1
    db 3
%endmacro

%define RET db 4

main:
    LIT hello
    LIT hello.len
    CALL 0xfffffffe
    RET

hello: db `Hello World!\n`
hello.len equ $ - hello

;$ nasm src/rs-3/x64-linux/vm.s -f elf64 -o vm.o
;$ nasm src/rs-3/hello.s -f elf64 -o hello.o
;$ ld vm.o hello.o -o hello -T src/rs-3/x64-linux/link.ld -z max-page-size=0x1000
;$ ./hello
;  Hello World!
