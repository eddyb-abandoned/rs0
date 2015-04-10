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
; RAX: General purpose temporary register
; RBX: Byte fetch register (BL = [IP++])

; NB: The return stack is not visible within the VM memory

; ## Instruction set
; 00 NOP
; 01 LIT8       S.push(imm8 as i32)
; 02 LIT32      S.push(imm32)
; 03 CALL       R.push(IP + 1), IP = S.pop()
; 04 RET        IP = R.pop()
; 05 JMP        IP = S.pop()
; 06 CMP        S.push([S.pop(), S.pop(), S.pop()][S.pop().cmp(S.pop())])
; 1x ALU        S.push([+, -, *, /, %, &, |, ^][op - 0x10](S.pop(), S.pop()))
; 18 DIVREM     a = S.pop(), b = S.pop(), S.push(b / a), S.push(b % a)
;
; 80-BF GET     S.push(S[op & 0x3f])
; C0-FF SET     S[op & 0x3f] = S.pop()
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

op.table:
    ; 00 - 0F
    dq op.nop, op.lit8, op.lit32, op.call, op.ret, op.jmp, op.cmp, op.ud
    times 8 dq op.ud
    ; 10 - 18
    dq alu.add, alu.sub, alu.mul, alu.and, alu.or, alu.xor, op.ud, op.ud
    dq alu.divrem
;    times 256-5 dq op.ud
op.last equ 0x18

op.nop:
    jmp vm.loop

op.lit8:
    mov bl, [vm.IP]
    inc vm.IP
    S.push ebx
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

msg.undef_builtin: db `Undefined builtin function\n`
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

op.dup:
    mov eax, [vm.SP]
    S.push eax
    jmp vm.loop

op.cmp:
    ; Stack: [a, b, lt, eq, gt] <- SP
    add vm.SP, 4 * 4 ; Point SP to a
    mov eax, [vm.SP]
    cmp eax, [vm.SP-4] ; a, b
    cmovl eax, [vm.SP-2*4] ; lt
    cmove eax, [vm.SP-3*4] ; eq
    cmovg eax, [vm.SP-4*4] ; gt
    mov [vm.SP], eax
    jmp vm.loop

%macro op.alu 1
    alu. %+ %1:
        S.pop eax
        %1 [vm.SP], eax
        jmp vm.loop
%endmacro

op.alu add
op.alu sub
op.alu and
op.alu or
op.alu xor

alu.mul:
    S.pop eax
    imul eax, [vm.SP]
    mov [vm.SP], eax
    jmp vm.loop

alu.divrem:
    mov eax, [vm.SP+4] ; dividend
    cdq ; edx:eax = sext eax

    idiv dword [vm.SP] ; divisor
    mov [vm.SP+4], eax ; quotient
    mov [vm.SP], edx ; remainder
    jmp vm.loop

op.getset:
    shl bl, 2 ; CF = op & 0x40, BL = (op & 0x3f) * 4
    jc op.set
op.get:
    mov eax, [vm.SP + rbx]
    S.push eax
    jmp vm.loop
op.set:
    S.pop eax
    mov [vm.SP + rbx], eax
    jmp vm.loop

msg.undef_op: db `Undefined instruction\n`
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
    mov bl, [vm.IP]
    inc vm.IP

    cmp bl, 0x80
    jae op.getset

    cmp bl, op.last
    ja op.ud

    jmp [op.table + ebx * 8]

GLOBAL _start
_start:
    ; Initialize VM registers
    mov vm.SP, vm.abs(0xfffff000)
    mov vm.IP, vm.abs(0x00001000)
    xor rbx, rbx

    ; Prevent one too many returns.
    R.push 0xffffffff

    jmp vm.loop
