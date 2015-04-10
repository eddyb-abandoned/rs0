BITS 64

; # RS-3 Dual Stack Machine

; ## Notation
; S: Data stack
; R: Return stack
; IP: Instruction pointer
; immN: Immediate bits following the opcode

; ## Memory layout
; 0x0000_0000..0x0000_1000 Zero page
; 0x0000_1000..0x1000_0000 Code & read-only data
; 0x1000_0000..0xfff0_0000 Arena
; 0xfff0_0000..0xfff0_1000 Guard page
; 0xfff0_1000..0xffff_f000 Data stack
; 0xffff_f000..0xffff_fffe Guard page

; At the end of the address space, within the upper
; guard page, there are several builtin call targets:
; 0xffff_fffe vm.print(data, len)
; 0xffff_ffff vm.exit()

; ## Register usage
; R8: Data stack pointer (S.P)
; RSP: Return stack pointer (R.P)
; R9: Instruction pointer (IP)

; NB: The return stack is not visible within the VM memory

; ## Instruction set
; 00 NOP
; 01 LIT8       S.push(imm8 as i32)
; 02 LIT32      S.push(imm32)
; 03 CALL       R.push(IP + 1), IP = S.pop()
; 04 RET        IP = R.pop()
; .. UD         vm.panic("Undefined instruction")

SECTION .text

%define vm.SP r8
%define vm.RP rsp
%define vm.IP r9
%define vm.IP.32 r9d
%define vm.abs(x) (0x100000000 + x)

; TODO check stack bounds
%macro vm.push_ 2
    sub vm. %+ %1 %+ P, 4
    mov [vm. %+ %1 %+ P], dword %2
%endmacro
%macro vm.pop_ 2
    mov dword %2, [vm. %+ %1 %+ P]
    add vm. %+ %1 %+ P, 4
%endmacro

%define S.push vm.push_ S,
%define S.pop vm.pop_ S,
%define R.push vm.push_ R,
%define R.pop vm.pop_ R,

op.table: dq op.nop, op.lit8, op.lit32, op.call, op.ret
op.last equ 4

op.nop:
    jmp vm.loop

op.lit8:
    xor eax, eax
    mov al, [vm.IP]
    inc vm.IP
    S.push eax
    jmp vm.loop

op.lit32:
    mov eax, [vm.IP]
    add vm.IP, 4
    S.push eax
    jmp vm.loop

op.call:
    R.push vm.IP.32
op.jmp:
    S.pop eax ; target
jmp.eax:
    mov vm.IP, vm.abs(0)
    add vm.IP, rax

    cmp vm.IP.32, 0
    jl jmp.builtin
    jmp vm.loop

msg.undef_builtin: db "Undefined builtin function", 0xa
msg.undef_builtin.len equ $ - msg.undef_builtin

jmp.builtin:
    inc vm.IP.32 ; 0xffff_ffff
    jz vm.exit

    inc vm.IP.32 ; 0xffff_fffe
    jnz jmp.builtin.undef

    S.pop edx ; len
    S.pop eax ; data
    mov rsi, vm.abs(0)
    add rsi, rax
    call vm.print
    jmp op.ret

jmp.builtin.undef:
    mov rsi, msg.undef_builtin
    mov rdx, msg.undef_builtin.len
    jmp vm.panic

op.ret:
    R.pop eax
    jmp jmp.eax

msg.undef_op: db "Undefined instruction", 0xa
msg.undef_op.len equ $ - msg.undef_op

op.ud:
    mov rsi, msg.undef_op
    mov rdx, msg.undef_op.len
    jmp vm.panic

vm.panic:
    call vm.print
    jmp vm.exit

vm.print:
    ; sys_write(stdout, data=rsi, len=rdx)
    mov rax, 1
    mov rdi, 1
    syscall
    ret

vm.exit:
    ; sys_exit(0)
    mov rax, 60
    mov rdi, 0
    syscall
    jmp $

vm.loop:
    xor eax, eax
    mov al, [vm.IP]
    inc vm.IP

    cmp al, op.last
    ja op.ud

    jmp [op.table + eax * 8]

GLOBAL _start
_start:
    ; Initialize VM registers
    mov vm.SP, vm.abs(0xfffff000)
    mov vm.IP, vm.abs(0x00001000)

    ; Prevent one too many returns.
    R.push 0xffffffff

    jmp vm.loop
