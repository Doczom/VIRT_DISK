
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

        DEBUG                   = 1
        __DEBUG__               = 1
        __DEBUG_LEVEL__         = 1  ; 1 = verbose, 2 = errors only

; standard driver stuff; version of driver model = 5
format PE DLL native 0.05

section '.flat' code readable writable executable
entry START
include '../drivers/proc32.inc'
include '../drivers/peimport.inc'
include '../drivers/macros.inc'

include '../drivers/fdo.inc'
; the start procedure (see the description above)
proc START c, state:dword, cmdline:dword
        xor     eax, eax ; set return value in case we will do nothing
        cmp     dword [state], 1
        jne     .nothing
        invoke  RegService, my_service, service_proc
        ret
.nothing:
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
        jb      .error_ret
        mov     eax, [ebx + IOCTL.output]
        mov     dword [eax], 1 ;API_VERSION
        xor     eax, eax
        jmp     .return

.add_disk:
        dec     ecx     ; check for DEV_ADD_DISK
        jnz     .del_disk

        cmp     [ebx + IOCTL.inp_size], sizeof.DISK_DEV
        jb      .error_ret

        invoke  KernelAlloc, sizeof.DISK_DEV
        test    eax, eax
        jz      .error_ret

        mov     edi, eax
        mov     esi, [ebx + IOCTL.input]
        mov     ecx, sizeof.DISK_DEV/4
        rep movsd

        ; check disk name

        ; add in list

        ; add disk
        mov     esi, eax ;save
        add     eax, DISK_DEV.DiskName
        invoke  DiskAdd, disk_functions, \
                         eax, esi, 0
        test    eax, eax
        mov     [esi + DISK_DEV.DiskHand], eax
        jz      .error_ret

        invoke  DiskMediaChanged, eax, 1

        jmp     .return

.del_disk:
        dec     ecx     ; check for DEV_DEL_DISK
        jnz     .get_root_list

        mov     ecx, [edx + IOCTL.input]
        mov     ecx, [ecx]
        call    disk_dev_check
        jnz     .error_ret

        ; del item list


        mov     eax, [ecx + DISK_DEV.DiskHand]
        invoke  DiskDel, eax

        jmp     .return

.get_root_list:
        dec     ecx     ; check for DEV_DEL_DISK
        jnz     .get_disk_info

        cmp     [ebx + IOCTL.out_size], 4*3
        jb      .error_ret
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

        mov     ecx, esi
        call    disk_dev_check
        jnz     .error_ret

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

; IN: ecx - ptr DISK_DEV
; OUT: ZF - found zF - not found
proc    disk_dev_check
        push    eax          ; 50h
        mov     eax, disk_root_list
@@:
        mov     eax, [eax]
        cmp     eax, disk_root_list
        jz      .nf
        cmp     eax, ecx
        jnz     @f
        pop     eax
        ret
.nf:
        test    eax, eax
        pop     eax      ;58h
        ret
endp

; DISK FUNCTION
proc    virt_disk_close stdcall, pdata
        mov     eax, [pdata]
        invoke  KernelFree, eax
        ret
endp

proc   disk_querymedia stdcall, pdata, mediainfo
        push    ecx edx
        pusha
        ;DEBUGF  1, "VIRT_DISK: querymedia\n"
        popa
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
        jz      .no_support

        DEBUGF  1, "VIRT_DISK: rd startsector %x\n", [startsector]
        lea     eax,[ecx + DISK_DEV.DiskPath]
        push    eax
        dec     esp
        mov     byte[esp], 0
        push    dword[buffer]

        mov     eax, [numsectors_ptr]
        mov     eax, [eax]
        DEBUGF  1, "VIRT_DISK: rd num %x\n", eax
        mul     dword[ecx + DISK_DEV.SectorSize]
        push    eax
        ; get offset for startsector
        mov     eax, dword[startsector]
        xor     edx, edx
        mul     dword[ecx + DISK_DEV.SectorSize]
        push    edx
        push    eax
        mov     eax, dword[startsector + 4]
        mul     dword[ecx + DISK_DEV.SectorSize]
        add     [esp + 4], eax
        push    dword 0 ;read file

        mov     ebx, esp
        ;pusha
        ;DEBUGF  1, "VIRT_DISK: error %x, %x, %x, %x, %x, %x %x\n", [ebx],[ebx+4],[ebx+8],[ebx+12],[ebx+16], [ebx+20], [ebx+24]
        ;popa
        invoke  FS_Service
        push    eax
        mov     ecx, [pdata]
        mov     eax, ebx
        xor     edx, edx
        div     dword[ecx + DISK_DEV.SectorSize]
        mov     edx, [numsectors_ptr]
        mov     [edx], eax
        DEBUGF  1, "VIRT_DISK: cory num %x \n", eax
        pop     eax

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
        jz      .no_support

        lea     eax,[ecx + DISK_DEV.DiskPath]
        push    eax
        dec     esp
        mov     byte[esp],0
        push    dword[buffer]

        mov     eax, [numsectors_ptr]
        mov     eax, [eax]
        mul     dword[ecx + DISK_DEV.SectorSize]
        push    eax
        ; get offset for startsector
        mov     eax, dword[startsector]
        xor     edx, edx
        mul     dword[ecx + DISK_DEV.SectorSize]
        push    edx
        push    eax
        xor     edx, edx
        mov     eax, dword[startsector + 4]
        mul     dword[ecx + DISK_DEV.SectorSize]
        add     [esp + 4], eax
        push     dword 3 ; write file
        mov     ebx, esp
        invoke  FS_Service
        mov     ecx, [numsectors_ptr]
        mov     [ecx], ebx
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
        dd      disk_functions.size
        dd      virt_disk_close
        dd      0 ; no need in .closemedia
        dd      disk_querymedia
        dd      virt_disk_rd
        dd      virt_disk_wr
        dd      0 ; no need in .flush
        dd      0
.size = $ - disk_functions

notify_fs: dd 7, 0, .message,0,0
           db '/sys/@notify',0
.message:  db '"message" -tdE',0
notify_fs2: dd 7, 0, .message,0,0
            db '/sys/@notify',0
.message:   db '"message2" -tdE',0
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

data fixups
end data

include_debug_strings