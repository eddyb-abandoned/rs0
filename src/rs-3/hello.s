SECTION code
code.__start__: times 0x1000 db 0x00
%define addr(x) (x - code.__start__)

%macro LIT 1
    db 2
    dd %1
%endmacro

%macro CALL 1
    LIT %1
    db 3
%endmacro

LIT addr(hello)
LIT hello.len
CALL 0xfffffffe
CALL 0xffffffff

hello: db "Hello World!", 0xa
hello.len equ $ - hello

SECTION stack nobits write
resb 0x100000

;$ nasm src/rs-3/x64-linux/vm.s -f elf64 -o vm.o
;$ nasm src/rs-3/hello.s -f elf64 -o hello.o
;$ ld vm.o hello.o -o hello --section-start=code=0x100000000 \
;$                          --section-start=stack=0x1fff00000
;$ ./hello
;  Hello World!