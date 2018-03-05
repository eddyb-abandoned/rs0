format ELF64

section ".text" executable

include "../x86_64/vm.s"

vm.print:
    ; sys_write(stdout, data=rsi, len=rdx)
    mov rax, 1
    mov rdi, 1
    syscall
    ret

vm.alloc:
    ; sys_mmap(0, len=rsi, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0)
    mov rax, 9
    mov rdi, 0
    mov rdx, 3
    push r10
    push r8
    push r9
    mov r10, 0x22
    mov r8, -1
    mov r9, 0
    syscall
    pop r9
    pop r8
    pop r10
    ret

vm.exit:
    ; sys_exit(0)
    mov rax, 60
    mov rdi, 0
    syscall
    jmp $
