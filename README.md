# VIRT_DISK
Driver for mounting RAW disk images in KolibriOS.

To demonstrate the operation of the driver, the virtdisk program was written. Program allows you to add, delete and view virtual disks.
![foto](https://github.com/Doczom/VIRT_DISK/blob/main/utils/scr_1.png)

Delete command:
 
   ___virtdisk -d <DISK_NUMBER>___

Information from disk:

   ___virtdisk -i <DISK_NUMBER>___

Add disk image in file system:

   ___virtdisk -a <IMAGE_PATH> -s <SECTOR_SIZE> -t <IMAGE_TYPE> -f <ACCESS_FLAGS>___

FLAGS:
 - ro - read only access
 - rw - read-write access

IMAGE_TYPE:
 - RAW

Input list all virtual disks:

   ___virtdisk -l___
