SRV_GETVERSION  = 0
ADD_VIRT_DISK   = 1
DEL_VIRT_DISK   = 2
GET_DISK_LIST   = 3
VIRT_DISK_INFO  = 4

Flag:
        .Ro = 1b
        .Wo = 10b
        .RW = 11b

; API

;int ADD_VIRT_DISK(IMAGE_ADD_STRUCT* image, int* disk_number)
;
;void DEL_VIRT_DISK(int* disk_number)
;
;void GET_DISK_LIST(void* params, void* get_data)
;params:
;.offset: dd ?
;.count:  dd ?
;
;get_data:
;.count_all_disk: dd ?
;.data_disks: db param.count*(sizeof.DISK_DEV - 8)
;
;void VIRT_DISK_INFO(int* disk_number, void* get_data.data_disks)
;