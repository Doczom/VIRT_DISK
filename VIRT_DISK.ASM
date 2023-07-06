
DISK_STATUS_OK              = 0 ; success
DISK_STATUS_GENERAL_ERROR   = -1; if no other code is suitable
DISK_STATUS_INVALID_CALL    = 1 ; invalid input parameters
DISK_STATUS_NO_MEDIA        = 2 ; no media present
DISK_STATUS_END_OF_MEDIA    = 3 ; end of media while reading/writing data

DEV_GET_LIST            equ 3 ; input ignored,
                              ; output = dword next and dword pref

; For all IOCTLs the driver returns one of the following error codes:
NO_ERROR                equ 0
ERROR_INVALID_IOCTL     equ 1 ; unknown IOCTL code

include '../drivers/struct.inc'

; Input structures:
Flag:
        .Ro = 1b
        .Wo = 10b

struct DISK_DEV
        next            rd      1
        pref            rd      1
        Flags           rd      1 ; 1-ro 2-wo 3-rw
        SectorSize      rd      1
        SectorCount     rd      2
        DiskHand        rd      1
        DiskName        rd      16 ;name disk, max
        DiskPath        rb      4096 ; max path len
ends

struct DISKMEDIAINFO
        Flags      dd ?
        SectorSize dd ?
        Capacity   dq ?
ends


; standard driver stuff; version of driver model = 5
format PE DLL native 0.05

section '.flat' code readable writable executable
data fixups
end data
entry START
include '../drivers/proc32.inc'
include '../drivers/peimport.inc'
include '../drivers/macros.inc'
; the start procedure (see the description above)
proc START c, state:dword, cmdline:dword
        xor     eax, eax ; set return value in case we will do nothing
        cmp     dword [state], 1
        jne     .nothing
        invoke  RegService, my_service, service_proc
        retn
.nothing:
        ;
                ret
endp

; get version
; add disk
; del disk
; get list disks
; get disk info
proc service_proc
        push    ebx esi edi
; 2. Get parameter from the stack: [esp+16] is the first parameter,
;    pointer to IOCTL structure.
        mov     ebx, [esp + 16]    ; edx -> IOCTL

        mov     ecx, [ebx + IOCTL.io_code]
        test    ecx, ecx        ; check for SRV_GETVERSION
        jnz     .add_disk

        cmp     [ebx + IOCTL.out_size], 4
        jl      .error_ret
        mov     eax, [ebx + IOCTL.output]
        mov     dword [eax], 1 ;API_VERSION
        xor     eax, eax
        jmp     .return

.add_disk:
        dec     ecx     ; check for DEV_ADD_DISK
        jnz     .del_disk

        cmp     [ebx + IOCTL.inp_size], sizeof.DISK_DEV
        jnz     .error_ret

        invoke  KernelAlloc, sizeof.DISK_DEV
        test    eax, eax
        jz      .error_ret
        mov     edi, eax
        mov     esi, [ebx + IOCTL.input]
        mov     ecx, sizeof.DISK_DEV/4
        rep movsd
        ; add in list

        ; add disk
        mov     esi, eax ;save
        invoke  DiskAdd, disk_functions, \
                         [eax + DISK_DEV.DiskName],\
                         eax, 0
        test    eax, eax
        jz      .error_ret

        invoke  DiskMediaChanged, [esi + DISK_DEV.DiskHand], 1

        xor     eax, eax
        jmp     .return

.del_disk:
        dec     ecx     ; check for DEV_DEL_DISK
        jnz     .get_root_list

        mov     eax, [edx + IOCTL.input]
        mov     ecx, [eax + DISK_DEV.DiskHand]
        invoke  DiskDel, ecx

        ; del item list

        xor     eax, eax
        jmp     .return

.get_root_list:
        dec     ecx     ; check for DEV_DEL_DISK
        jnz     .get_disk_info

        cmp     [ebx + IOCTL.out_size], 4*3
        jl      .error_ret
        mov     eax, [ebx + IOCTL.output]
        mov     dword [eax], disk_root_list
        mov     ecx, [disk_root_list]
        mov     [eax + 4], ecx
        mov     ecx, [disk_root_list + 4]
        mov     [eax + 8], ecx
        xor     eax, eax

        jmp     .return

.get_disk_info:
        dec     ecx
        jnz     .error_ret

        cmp     [ebx + IOCTL.inp_size], 4
        jnz     .error_ret
        cmp     [ebx + IOCTL.out_size], sizeof.DISK_DEV
        jnz     .error_ret
        mov     esi, [ebx + IOCTL.input]
        mov     esi, [esi]
        mov     edi, [ebx + IOCTL.output]
        mov     ecx, sizeof.DISK_DEV/4
        rep movsd
        xor     eax, eax
        jmp     .return

.error_ret:
        mov     eax, -1
.return:
        pop     edi esi ebx
        retn    4
endp

proc    virt_disk_close stdcall, pdata
        mov     edx, [pdata]
        invoke  KernelFree, eax
        ret
endp

proc   disk_querymedia stdcall, pdata, mediainfo
        push    ecx edx
        mov     eax, [mediainfo]
        mov     edx, [pdata]
        mov     [eax + DISKMEDIAINFO.Flags], 0
        mov     ecx, [edx + DISK_DEV.SectorSize]
        mov     [eax + DISKMEDIAINFO.SectorSize], ecx
        mov     ecx, [edx + DISK_DEV.SectorCount]
        mov     dword[eax + DISKMEDIAINFO.Capacity], ecx
        mov     ecx, [edx + DISK_DEV.SectorCount + 4]
        mov     dword[eax + DISKMEDIAINFO.Capacity + 4], ecx
        pop     edx ecx
        xor     eax, eax
        ret
endp

proc    virt_disk_rd stdcall pdata: dword,\
                             buffer: dword,\
                             startsector: qword,\
                             numsectors_ptr:dword
        pusha
        mov     ecx, [pdata]
        test    [ecx + DISK_DEV.Flags], Flag.Ro
        jnz     .no_support

        push    dword[ecx + DISK_DEV.DiskPath]
        dec     esp
        mov     byte[esp], 0
        push    dword[buffer]

        mov     eax, [numsectors_ptr]
        mov     eax, [eax]
        xor     edx, edx
        mul     dword[ecx + DISK_DEV.SectorSize]
        push    eax
        push    dword[startsector + 4]
        push    dword[startsector]
        push    dword 1 ;read file

        mov     ebx, esp
        invoke  FS_Service
        add     esp, 6*4+1 ; size FS struct
        test    eax, eax
        popa
        jz      @f
        mov     eax, 1
@@:

        ret
.no_support:
        popa
        mov     eax, -1 ;error
        ret
endp

proc    virt_disk_wr stdcall pdata: dword, buffer: dword, startsector: qword, numsectors_ptr:dword
        pusha
        mov     ecx, [pdata]
        test    [ecx + DISK_DEV.Flags], Flag.Wo
        jnz     .no_support

        push    dword[ecx + DISK_DEV.DiskPath]
        dec     esp
        mov     byte[esp],0
        push    dword[buffer]

        mov     eax, [numsectors_ptr]
        mov     eax, [eax]
        xor     edx, edx
        mul     dword[ecx + DISK_DEV.SectorSize]
        push    eax
        push    dword[startsector + 4]
        push    dword[startsector]
        push     dword 3 ; write file

        mov     ebx, esp
        invoke  FS_Service
        add     esp, 6*4+1 ; size FS struct
        test    eax, eax
        popa
        jz      @f
        mov     eax, 1
@@:
        ret

.no_support:
        popa
        mov             eax, -1 ;error
        ret
endp


disk_root_list:
        dd      disk_root_list
        dd      disk_root_list

align 4
disk_functions:
        dd      disk_functions_end - disk_functions
        dd      virt_disk_close
        dd      0 ; no need in .closemedia
        dd      disk_querymedia
        dd      virt_disk_rd
        dd      virt_disk_wr
        dd      0 ; no need in .flush
        dd      0
disk_functions_end:

; The kernel calls this function when initializing cache subsystem for
; the media. This call allows the driver to adjust the cache size.
proc tmpdisk_adjust_cache_size
  virtual at esp+4
    .userdata dd ?
    .suggested_size dd ?
  end virtual
; Since tmpdisk does not need cache, just return 0.
        xor     eax, eax
        retn    8
endp

my_service      db      'VIRT_DISK',0
