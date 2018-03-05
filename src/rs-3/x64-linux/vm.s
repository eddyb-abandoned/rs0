format ELF64

; # RS-3 Dual Stack Machine

; ## Notation
; S: Data stack
; R: Return stack
; IP: Instruction pointer
; var(u)intN: Immediate bits following the opcode, encoded in LUB128

; ## Memory layout
; 0x0000_0000..0x0000_1000 Zero page
; 0x0000_1000..0x0000_2000 VM native code
; 0x0000_2000..0x1000_0000 Read-only data
; 0xfff0_0000..0xfff0_1000 Guard page
; 0xfff0_1000..0xffff_f000 Data stack
; 0xffff_f000..0xffff_fffe Guard page
; 0x1_0000_0000.. Bytecode

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
; 01 LIT32      S.push(varuint32)
; 02 CALL       R.push(IP + 1), IP = S.pop()
; 03 RET        IP = R.pop()
; 04 JMP        IP = S.pop()
; 05 CMP        S.push([S.pop(), S.pop(), S.pop()][S.pop().cmp(S.pop())])
; 06 GET        S.push(S[varuint32])
; 07 SET        S[varuint32] = S.pop()
; 1x ALU        S.push([+, -, *, /s, /u, %s, %u, &, |, ^][op - 0x10](S.pop(), S.pop()))
;
; .. UD         vm.panic("Undefined instruction")

section "vm.native" executable

vm.SP equ r8
vm.RP equ rsp
vm.IP equ r9d
vm.IP.base equ r10
vm.IP.mem equ r10 + r9

; TODO check stack bounds
macro vm.push_ r, x {
    sub vm.#r#P, 4
    mov [vm.#r#P], dword x
}
macro vm.pop_ r, x {
    mov dword x, [vm.#r#P]
    add vm.#r#P, 4
}

macro S.push x {vm.push_ S, x}
macro S.pop x {vm.pop_ S, x}
macro R.push x {vm.push_ R, x}
macro R.pop x {vm.pop_ R, x}

imm.varuint32:
    xor eax, eax
    xor cl, cl
imm.varuint32.loop:
    inc vm.IP
    mov bl, [vm.IP.mem - 1]
    mov edx, ebx
    and edx, 0x7f
    shl edx, cl
    or eax, edx
    add cl, 7
    test bl, 0x80
    jnz imm.varuint32.loop
    ret

imm.varint32:
    xor eax, eax
    xor cl, cl
imm.varint32.loop:
    inc vm.IP
    mov bl, [vm.IP.mem - 1]
    mov edx, ebx
    and edx, 0x7f
    shl edx, cl
    or eax, edx
    add cl, 7
    test bl, 0x80
    jnz imm.varint32.loop
    ; Sign-extend the last 7-bit group
    neg cl
    add cl, 32
    cmp cl, 0
    jl imm.varint32.ret
    shl eax, cl
    sar eax, cl
imm.varint32.ret:
    ret

op.table:
    ; 00
    dq op.nop, op.lit32, op.call, op.ret, op.jmp, op.cmp, op.get, op.set
    ; 08
    times 8 dq op.ud
    ; 10
    dq alu.add, alu.sub, alu.mul, alu.div_s, alu.div_u, alu.rem_s, alu.rem_u, alu.and, alu.or, alu.xor
op.table.len = ($ - op.table) / 8

op.nop:
    jmp vm.loop

op.lit32:
    call imm.varint32
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
    mov rcx, 0x100002000
    add rsi, rcx ; HACK(eddyb) clean this up
    call vm.print
    jmp op.ret

op.jmp.builtin.undef:
    mov rsi, msg.undef_builtin
    mov rdx, msg.undef_builtin.len
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

macro op.alu op {
    alu.#op:
        S.pop eax
        op [vm.SP], eax
        jmp vm.loop
}

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

macro op.alu.divrem op, div, out {
    alu.#op:
        S.pop ecx ; divisor
        mov eax, [vm.SP] ; dividend
        if div eq idiv
            cdq ; edx:eax = sext eax
        else
            xor edx, edx
        end if

        div ecx
        mov [vm.SP], out
        jmp vm.loop
}

op.alu.divrem div_s, idiv, eax
op.alu.divrem div_u, div, eax
op.alu.divrem rem_s, idiv, edx
op.alu.divrem rem_u, div, edx

op.get:
    call imm.varuint32
    mov eax, [vm.SP + rax * 4]
    S.push eax
    jmp vm.loop

op.set:
    call imm.varuint32
    S.pop ecx
    mov [vm.SP + rax * 4], ecx
    jmp vm.loop

op.ud:
    mov rsi, msg.undef_op
    mov rdx, msg.undef_op.len
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

public vm.start
vm.start:
    ; Initialize VM registers
    mov vm.IP.base, 0x200000000
    mov vm.IP, 0x00000000
    mov vm.SP, 0x1fffff000
    xor ebx, ebx

    ; Prevent one too many returns.
    R.push 0xffffffff

vm.loop:
    mov bl, [vm.IP.mem]
    inc vm.IP

    cmp bl, op.table.len
    jae op.ud

    mov rcx, op.table
    jmp qword [rcx + rbx * 8]

msg.undef_op: db "Undefined instruction", 10
msg.undef_op.len = $ - msg.undef_op

msg.undef_builtin: db "Undefined builtin function", 10
msg.undef_builtin.len = $ - msg.undef_builtin

section "vm.stack" writeable
