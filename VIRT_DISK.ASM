;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                                                                 ;;
;; Copyright (C) KolibriOS team 2023. All rights reserved.         ;;
;; Distributed under terms of the GNU General Public License       ;;
;;                                                                 ;;
;;  Virtual disk driver for KolibriOS                              ;;
;;                                                                 ;;
;;    Written by Mikhail Frolov aka Doczom                         ;;
;;                                                                 ;;
;;          GNU GENERAL PUBLIC LICENSE                             ;;
;;             Version 2, June 1991                                ;;
;;                                                                 ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DISK_STATUS_OK              = 0 ; success
DISK_STATUS_GENERAL_ERROR   = -1; if no other code is suitable
DISK_STATUS_INVALID_CALL    = 1 ; invalid input parameters
DISK_STATUS_NO_MEDIA        = 2 ; no media present
DISK_STATUS_END_OF_MEDIA    = 3 ; end of media while reading/writing data

; For all IOCTLs the driver returns one of the following error codes:
NO_ERROR                equ 0
ERROR_INVALID_IOCTL     equ 1 ; unknown IOCTL code

maxPathLength = 1000h

include '../drivers/struct.inc'

; TODO list:
; add support VDI image

; Input structures:
Flag:
        .Ro = 1b
        .Wo = 10b
        .RW = 11b

struct DISK_DEV
        next            rd      1
        pref            rd      1
        SectorCount     rd      2
        DiskHandle      rd      1
        DiskNumber      rd      1
        DiskName        rd      16 ;name disk, max
        Flags           rd      1 ; 1-ro 2-wo 3-rw
        TypeImage       rd      1 ; 0-raw 1-vhd 2-vdi 3-imd
        SectorSize      rd      1
        DiskPath        rb      maxPathLength
ends
struct  IMAGE_ADD_STRUCT
        Flags           rd      1 ; 1-ro 2-wo 3-rw
        TypeImage       rd      1 ; 0-raw 1-vhd 2-vdi 3-imd
        SectorSize      rd      1
        DiskPath        rb      maxPathLength
ends

struct DISKMEDIAINFO
        Flags      dd ?
        SectorSize dd ?
        Capacity   dq ?
ends

        DEBUG                   = 1
        __DEBUG__               = 1
        __DEBUG_LEVEL__         = 1  ; 1 = verbose, 2 = errors only

format PE DLL native 0.05
entry START

section '.flat' code readable writable executable

include '../drivers/proc32.inc'
include '../drivers/peimport.inc'
include '../drivers/macros.inc'

include '../drivers/fdo.inc'

proc START c, state:dword, cmdline:dword
        xor     eax, eax ; set return value in case we will do nothing
        cmp     dword [state], 1
        jne     .nothing

        mov     ecx, disk_list_lock
        invoke  MutexInit

        DEBUGF  1, "VIRT_DISK: driver loaded\n"
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

        cmp     [ebx + IOCTL.inp_size], sizeof.IMAGE_ADD_STRUCT
        jb      .error_ret

        cmp     [ebx + IOCTL.out_size], 4
        jb      .error_ret

        invoke  KernelAlloc, sizeof.DISK_DEV
        test    eax, eax
        jz      .error_ret

        mov     ecx,[ebx + IOCTL.output]
        mov     [ecx], eax

        push    eax
        mov     edi, eax
        mov     ecx, sizeof.DISK_DEV/4
        xor     eax, eax
        rep stosd
        pop     eax

        mov     edi, eax
        add     edi, DISK_DEV.Flags
        mov     esi, [ebx + IOCTL.input]
        mov     ecx, sizeof.IMAGE_ADD_STRUCT/4
        rep movsd

        mov     esi, eax ;save

        pusha
        call    get_free_num
        jnz     .not_free_num

        mov     [esi + DISK_DEV.DiskNumber], eax
        mov     dword[esi + DISK_DEV.DiskName], 'vd'
        ; creating name

        mov     ebx, esi
        mov     esi, esp
        mov     ecx, 10
@@:
        xor     edx, edx
        div     ecx
        add     edx,'0'
        dec     esi
        mov     byte[esi], dl
        test    eax, eax
        jnz     @b

        mov     ecx, esp
        sub     ecx, esi
        lea     edi, [ebx + DISK_DEV.DiskName + 2]
        rep movsb
        mov     byte[edi], 0
        test    eax, eax
.not_free_num:
        popa
        jnz     .add_disk.error

        ; init image
        mov     eax, [esi + DISK_DEV.TypeImage]
        cmp     eax, image_type.max_num
        ja      .add_disk.error

        call    dword[image_type + eax*8]
        test    eax, eax
        jnz     .add_disk.error

        ; add disk
        mov     eax, [esi + DISK_DEV.TypeImage]
        lea     ecx,[esi + DISK_DEV.DiskName]
        invoke  DiskAdd, dword[image_type + eax*8 + 4] , \
                         ecx, esi, 0
        test    eax, eax
        mov     [esi + DISK_DEV.DiskHandle], eax
        jz      .error_ret

        invoke  DiskMediaChanged, eax, 1

        ; add in list

        mov     ecx, disk_list_lock
        invoke  MutexLock

        mov     dword[esi], disk_root_list
        mov     eax, [disk_root_list + 4]
        mov     [esi + 4], eax
        mov     [eax], esi
        mov     [disk_root_list + 4], esi

        mov     ecx, disk_list_lock
        invoke  MutexUnlock

        jmp     .return
.add_disk.error:
        invoke  KernelFree, esi
        jmp     .error_ret


.del_disk:
        dec     ecx     ; check for DEV_DEL_DISK
        jnz     .get_root_list

        mov     ecx, [ebx + IOCTL.input]
        mov     ecx, [ecx]
        call    disk_dev_check
        jnz     .error_ret

        cmp     [ecx + DISK_DEV.DiskHandle], 0
        jz      .error_ret
        mov     eax, [ecx + DISK_DEV.DiskHandle]
        mov     [ecx + DISK_DEV.DiskHandle], 0
        invoke  DiskDel, eax

        xor     eax, eax
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
        mov     eax, ERROR_INVALID_IOCTL
.return:
        pop     edi esi ebx
        retn    4
endp

; IN: ecx - ptr DISK_DEV
; OUT: ZF - found zF - not found
proc    disk_dev_check
        push    eax
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
        pop     eax
        ret
endp

; OUT: eax - number free disk
;      Zf - good zf - not found
proc    get_free_num
        ; lock disk list
        mov     ecx, disk_list_lock
        invoke  MutexLock

        xor    eax, eax
        mov    edx, disk_root_list
@@:
        mov     edx, [edx]
        cmp     edx, disk_root_list
        jz      @f
        cmp     eax, [edx + DISK_DEV.DiskNumber]
        jnz     @b

        inc     eax
        jnz     @b

        test    edx, edx ; random :)
@@:

        pushfd
        push    eax
        ; unlock disk list
        mov     ecx, disk_list_lock
        invoke  MutexUnlock
        pop     eax
        popfd
        ret
endp

; RAW IMAGE DISK FUNCTIONS
proc    raw_disk_close stdcall, pdata
        push    esi
        mov     esi, [pdata]
        ; del item list
        mov     ecx, disk_list_lock
        invoke  MutexLock

        mov     eax, [esi]
        mov     edx, [esi + 4]
        mov     [eax + 4], edx
        mov     [edx], eax

        mov     ecx, disk_list_lock
        invoke  MutexUnlock

        pop     esi

        mov     eax, [pdata]
        invoke  KernelFree, eax
        ret
endp

proc   disk_querymedia stdcall, pdata, mediainfo
        mov     eax, [mediainfo]
        mov     edx, [pdata]
        mov     [eax + DISKMEDIAINFO.Flags], 0
        mov     ecx, [edx + DISK_DEV.SectorSize]
        mov     [eax + DISKMEDIAINFO.SectorSize], ecx
        mov     ecx, [edx + DISK_DEV.SectorCount]
        mov     dword[eax + DISKMEDIAINFO.Capacity], ecx
        mov     ecx, [edx + DISK_DEV.SectorCount + 4]
        mov     dword[eax + DISKMEDIAINFO.Capacity + 4], ecx
        xor     eax, eax
        ret
endp

proc    raw_disk_rd stdcall pdata: dword,\
                            buffer: dword,\
                            startsector: qword,\
                            numsectors_ptr:dword

        mov     ecx, [pdata]
        test    [ecx + DISK_DEV.Flags], Flag.Ro
        jz      .no_support

        pusha
        lea     eax,[ecx + DISK_DEV.DiskPath]
        push    eax
        dec     esp
        mov     byte[esp], 0
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
        mov     eax, dword[startsector + 4]
        mul     dword[ecx + DISK_DEV.SectorSize]
        add     [esp + 4], eax
        push    dword 0 ;read file

        mov     ebx, esp
        invoke  FS_Service
        push    eax
        mov     ecx, [pdata]
        mov     eax, ebx
        xor     edx, edx
        div     dword[ecx + DISK_DEV.SectorSize]
        mov     edx, [numsectors_ptr]
        mov     [edx], eax
        pop     eax

        add     esp, 6*4+1 ; size FS struct
        test    eax, eax
        popa
        jz      @f
        mov     eax, 1
        ret
@@:
        xor     eax, eax
        ret
.no_support:
        mov     eax, DISK_STATUS_GENERAL_ERROR
        ret
endp


proc    raw_disk_wr stdcall pdata: dword,\
                            buffer: dword,\
                            startsector: qword,\
                            numsectors_ptr:dword

        mov     ecx, [pdata]
        test    [ecx + DISK_DEV.Flags], Flag.Wo
        jz      .no_support

        pusha
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
        push    dword 3 ; write file
        mov     ebx, esp
        invoke  FS_Service

        push    eax
        mov     ecx, [pdata]
        mov     eax, ebx
        xor     edx, edx
        div     dword[ecx + DISK_DEV.SectorSize]
        mov     edx, [numsectors_ptr]
        mov     [edx], eax
        pop     eax

        add     esp, 6*4+1 ; size FS struct
        test    eax, eax
        popa
        jz      @f
        mov     eax, 1
        ret
@@:
        xor     eax, eax
        ret

.no_support:
        mov     eax, DISK_STATUS_GENERAL_ERROR
        ret
endp


disk_root_list:
        dd      disk_root_list
        dd      disk_root_list
disk_list_lock: MUTEX

image_type:
        ;  init function, table disk function
        dd raw_image_init, raw_disk_functions
        ; vdi
.max_num = ($ - image_type - 8) / 8; 8 - item size

align 4
; esi - ptr to DISK_DEV
;WARNING: raw image size >=2tb not supported.

proc    raw_image_init
        sub     esp, 40 ; for file_info
        mov     ecx, esp

        pusha
        lea     eax,[esi + DISK_DEV.DiskPath]
        push    eax
        dec     esp
        mov     byte[esp],0
        push    ecx
        xor     eax, eax
        push    eax eax eax
        push    dword 5

        mov     ebx, esp
        invoke  FS_Service
        add     esp, 6*4+1
        test    eax, eax
        popa
        lea     esp,[esp + 40]
        jnz     .err

        ; WARNING: Not working with stack, destroys the structure!
        mov     eax, [ecx + 32]
        mov     edx, [ecx + 36]
        test    eax, eax
        jz      .err

        div     dword[esi + DISK_DEV.SectorSize]   ; undefined exeption
        mov     [esi + DISK_DEV.SectorCount], eax
        mov     [esi + DISK_DEV.SectorCount + 4], 0
        ; END WARNING

        xor     eax, eax
        ret
.err:
        or      eax, -1
        ret
endp

align 4
raw_disk_functions:
        dd      .size
        dd      raw_disk_close
        dd      0 ; no need in .closemedia
        dd      disk_querymedia
        dd      raw_disk_rd
        dd      raw_disk_wr
        dd      0 ; no need in .flush
        dd      disk_adjust_cache_size
.size = $ - raw_disk_functions

proc disk_adjust_cache_size
  virtual at esp+4
    .userdata dd ?
    .suggested_size dd ?
  end virtual
        xor     eax, eax
        retn    8
endp

my_service      db      'VIRT_DISK',0

data fixups
end data

include_debug_strings