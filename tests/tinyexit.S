@ tinyexit: the smallest ARM EABI program, exit(0) with no libc: an exec that costs only the kernel
	.text
	.globl	_start
_start:
	mov	r0, #0
	mov	r7, #1		@ __NR_exit
	svc	#0
