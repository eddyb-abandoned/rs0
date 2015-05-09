BITS 64

; # RS-3 Dual Stack Machine

; ## Notation
; S: Data stack
; R: Return stack
; IP: Instruction pointer
; immN: Immediate bits following the opcode

; ## Memory layout
; 0x0000_0000..0x0000_1000 Zero page
; 0x0000_1000..0x0000_2000 VM native code
; 0x0000_2000..0x1000_0000 Code & read-only data
; 0x1000_0000..0xfff0_0000 Arena
; 0xfff0_0000..0xfff0_1000 Guard page
; 0xfff0_1000..0xffff_f000 Data stack
; 0xffff_f000..0xffff_fffe Guard page

; At the end of the address space, within the upper
; guard page, there are several builtin call targets:
; 0xffff_fffe vm.print(data, len)
; 0xffff_ffff vm.exit()

; ## Register usage
; R8D: Data stack pointer (S.P)
; RSP: Return stack pointer (R.P)
; R9D: Instruction pointer (IP)
; EAX: General purpose temporary register
; EBX: Byte fetch register (BL = [IP++])

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

SECTION vm.native exec align=16

%define vm.SP r8d
%define vm.RP rsp
%define vm.IP r9d

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
    dw op.nop, op.lit8, op.lit32, op.call, op.ret, op.jmp, op.cmp, op.ud
    times 8 dw op.ud
    ; 10 - 18
    dw alu.add, alu.sub, alu.mul, alu.and, alu.or, alu.xor, op.ud, op.ud
    dw alu.divrem
op.last equ 0x18
;    times 256-op.last dq op.ud

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
    R.push vm.IP
op.jmp:
    S.pop vm.IP
op.jmp.check:
    cmp vm.IP, 0
    jl op.jmp.builtin
    jmp vm.loop

op.jmp.builtin:
    inc vm.IP ; 0xffff_ffff
    jz vm.exit

    inc vm.IP ; 0xffff_fffe
    jnz op.jmp.builtin.undef

    S.pop edx ; len
    S.pop esi ; data
    call vm.print
    jmp op.ret

op.jmp.builtin.undef:
    mov esi, msg.undef_builtin
    mov edx, msg.undef_builtin.len
    jmp vm.panic

op.ret:
    R.pop vm.IP
    jmp op.jmp.check

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
    mov eax, [vm.SP + ebx]
    S.push eax
    jmp vm.loop
op.set:
    S.pop eax
    mov [vm.SP + ebx], eax
    jmp vm.loop

op.ud:
    mov esi, msg.undef_op
    mov edx, msg.undef_op.len
vm.panic:
    push qword vm.exit
vm.print:
    ; sys_write(stdout, data=esi, len=edx)
    mov eax, 1
    mov edi, 1
    syscall
    ret

vm.exit:
    ; sys_exit(0)
    mov eax, 60
    mov edi, 0
    syscall
    jmp $

GLOBAL vm.start
vm.start:
    ; Initialize VM registers
    mov vm.IP, vm.code.start
    mov vm.SP, vm.stack.end
    xor ebx, ebx

    ; Prevent one too many returns.
    R.push 0xffffffff

vm.loop:
    mov bl, [vm.IP]
    inc vm.IP

    cmp bl, 0x80
    jae op.getset

    cmp bl, op.last
    ja op.ud

    jmp [op.table + ebx * 4]

msg.undef_op: db `Undefined instruction\n`
msg.undef_op.len equ $ - msg.undef_op

msg.undef_builtin: db `Undefined builtin function\n`
msg.undef_builtin.len equ $ - msg.undef_builtin

SECTION vm.code
vm.code.start:

SECTION vm.stack nobits write
resb 0xfffff000 - 0xfff01000
vm.stack.end:
