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
%define JMP db 5

%macro CMP 3
    LIT %1
    LIT %2
    LIT %3
    db 6
%endmacro

%macro JMP.LT 1
    CMP %1, %%after, %%after
    JMP
    %%after:
%endmacro

%macro JMP.GT 1
    CMP %%after, %%after, %1
    JMP
    %%after:
%endmacro

%macro JMP.GE 1
    CMP %%after, %1, %1
    JMP
    %%after:
%endmacro

%macro JMP.NE 1
    CMP %1, %%after, %1
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

%macro SWAP 2 ; a, b -> b, a (for SWAP 0, 1)
    GET %1      ; a, b       -> a, b, b
    GET %2 + 1  ; a, b, b    -> a, b, b, a
    SET %1 + 1  ; a, b, b, a -> a, a, b
    SET %2      ; a, a, b    -> b, a
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
        CALL print.dec

        ; print(" ")
        LIT space
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

        ; if i < 100 { continue }
        GET 0
        LIT 100
        JMP.LT main.loop

    ; print("\n")
    LIT newline
    LIT 1
    CALL 0xfffffffe
    RET

print.dec:
    GET 0
    LIT 0
    JMP.GE print.dec.positive
    ; print("-")
    LIT minus
    LIT 1
    CALL 0xfffffffe

    ; x = -x
    LIT -1
    MUL
    print.dec.positive:

    ; Leave a stop "mark" on the stack.
    ; x -> 10, x
    GET 0 ; x -> x, x
    LIT 10 ; x, x -> x, x, 10
    SET 1 ; x, x, 10 -> 10, x

    ; Split each digit into a stack slot.
    ; 10, abcd -> 10, d, c, b, a
    print.dec.digit_loop:
        ; x -> q = x / 10, r = x % 10
        LIT 10
        DIVREM

        ; q, r -> r, q
        SWAP 0, 1

        ; if q != 0 { continue }
        GET 0
        LIT 0
        JMP.NE print.dec.digit_loop
    DROP

    print.dec.print_loop:
        ; print(digits[x % 10])
        LIT digits
        ADD
        LIT 1
        CALL 0xfffffffe

        ; if top < 10 { continue }
        GET 0
        LIT 10
        JMP.LT print.dec.print_loop
    DROP
    RET

space: db " "
newline: db `\n`
minus: db "-"
digits: db "0123456789"

;$ nasm src/rs-3/x64-linux/vm.s -f elf64 -o vm.o
;$ nasm src/rs-3/fib.s -f elf64 -o fib.o
;$ ld vm.o fib.o -o fib -T src/rs-3/x64-linux/link.ld -z max-page-size=0x1000
;$ ./fib
; 1 1 2 3 5 8 13 21 34 55 89 144 233 377 61 987 1597 2584 ...
