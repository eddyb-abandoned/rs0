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

%define RET db 4
%define JMP db 5

%macro CMP 3
    LIT %1
    LIT %2
    LIT %3
    db 6
%endmacro

%macro JMP.LT 1
    CMP %1, addr(%%after), addr(%%after)
    JMP
    %%after:
%endmacro

%macro JMP.GT 1
    CMP addr(%%after), addr(%%after), %1
    JMP
    %%after:
%endmacro

%macro JMP.GE 1
    CMP addr(%%after), %1, %1
    JMP
    %%after:
%endmacro

%macro JMP.NE 1
    CMP %1, addr(%%after), %1
    JMP
    %%after:
%endmacro

%define ADD db 0x10
%define SUB db 0x11
%define MUL db 0x12
%define DIVREM db 0x18

%macro INC 0
    LIT 1
    ADD
%endmacro

%macro GET 1
    db 0x80 + %1
%endmacro

%macro SET 1
    db 0xc0 + %1
%endmacro

%macro DROP 0 ; a, b -> a
    GET 0 ; a, b    -> a, b, b
    SUB   ; a, b, b -> a, 0
    ADD   ; a, 0,   -> a
%endmacro

main:
    LIT 0 ; a = 0
    LIT 1 ; b = 1
    LIT 0 ; i = 0
    main.loop:
        ; print.dec(b)
        GET 1
        CALL addr(print.dec)

        ; print(" ")
        LIT addr(space)
        LIT 1
        CALL 0xfffffffe

        ; i += 1
        INC

        ; (a, b) = (b, a + b)
        GET 2 ; a
        GET 2 ; b
        ADD ; a + b
        GET 2 ; b
        SET 3 ; a' = b
        SET 1 ; b' = a + b

        ; if i < 50 { continue }
        GET 0
        LIT 50
        JMP.LT addr(main.loop)

    ; print("\n")
    LIT addr(newline)
    LIT 1
    CALL 0xfffffffe
    RET

print.dec:
    GET 0
    LIT 0
    JMP.GE addr(print.dec.positive)
    ; print("-")
    LIT addr(minus)
    LIT 1
    CALL 0xfffffffe

    ; x = -x
    LIT -1
    MUL
    print.dec.positive:

    ; x -> 0(r), x
    GET 0 ; x -> x, x
    LIT 0 ; x, x -> x, x, 0
    SET 1 ; x, x, 0 -> 0, x

    print.dec.reverse_loop:
        ; x -> x / 10, x % 10
        LIT 10
        DIVREM

        ; r = r * 10 + x % 10
        GET 2 ; r
        LIT 10
        MUL ; r * 10
        ADD ; r * 10 + x % 10
        SET 1 ; r

        ; if (x / 10) != 0 { continue }
        GET 0
        LIT 0
        JMP.NE addr(print.dec.reverse_loop)
    DROP

    print.dec.print_loop:
        ; x -> x / 10, x % 10
        LIT 10
        DIVREM

        ; print(digits[x % 10])
        LIT addr(digits)
        ADD
        LIT 1
        CALL 0xfffffffe

        ; if (x / 10) != 0 { continue }
        GET 0
        LIT 0
        JMP.NE addr(print.dec.print_loop)
    DROP
    RET

space: db " "
newline: db `\n`
minus: db "-"
digits: db "0123456789"

SECTION stack nobits write
resb 0xfe000

;$ nasm src/rs-3/x64-linux/vm.s -f elf64 -o vm.o
;$ nasm src/rs-3/fib.s -f elf64 -o fib.o
;$ ld vm.o fib.o -o fib --section-start=code=0x100000000 \
;$                      --section-start=stack=0x1fff01000
;$ ./fib
; 1 1 2 3 5 8 13 21 34 55 89 144 233 377 61 987 1597 2584 ...
