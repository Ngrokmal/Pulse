#include <cstring>
#include <pthread.h>
#include <thread>
#include <cstring>
#include <jni.h>
#include <unistd.h>
#include <fstream>
#include <iostream>
#include "KittyMemory/MemoryPatch.h"
#include "Includes/obfuscate.h"
#include "Includes/Utils.h"
#include "Includes/Macros.h"
#include "Tools.h"
#define targetLibName OBFUSCATE("libanort.so")
#define targetLibName OBFUSCATE("libanogs.so")
#define targetLibName OBFUSCATE("libUE4.so")
#define targetLibName OBFUSCATE("libgcloud.so")
#include "Includes/Macros.h"
//------------HOOKS

//Crash Fixer
#define _BYTE  uint8_t
#define _WORD  uint16_t
#define _DWORD uint32_t
#define _QWORD uint64_t

uintptr_t customHookAddress = 0;

DWORD libanogsBase = 0;
DWORD libUE4Base = 0;
DWORD libanortBase = 0;
DWORD libgcloudBase = 0;
DWORD libEGLBase = 0;
DWORD libanogsAlloc = 0;
DWORD libUE4Alloc = 0;
DWORD libEGLAlloc = 0; 




unsigned int libanogsSize = 0x33244D;
unsigned int libUE4Size = 0x470BA4D;
//unsigned int libcSize = 0xC3000;
unsigned int libEglSize = 0x2000;
char *Offset;
DWORD NewBase = 0;
//typedef int64_t __int64 ;


    void* hook_memcpy(char *dest, const char *src, size_t size)
{
    if ((DWORD)src >= libanogsBase && (DWORD)src <= (DWORD)(libanogsBase + libanogsSize))
    {
        Offset = (char *)(src - (char *)libanogsBase);
        NewBase = libanogsAlloc;
        src = &Offset[NewBase];
        return memcpy(dest, src, size);
    }
    if ((DWORD)src >= libUE4Base && (DWORD)src <= (DWORD)(libUE4Base + libUE4Size))
    {
        Offset = (char *)(src - (char *)libUE4Base);
        NewBase = libUE4Alloc;
        src = &Offset[NewBase];
        return memcpy(dest, src, size);
    }
    return memcpy(dest, src, size);
}



   

///(1)

int sub_4AAC0(int a1) 
{
 return 0;
}

int __fastcall (*Sub_97794)(int a1, const char* a2, int a3);

int __fastcall OSub_97794(int a1, const char* a2, int a3)
{
   if (strstr(a2, ("various_opcode")) ||
     strstr(a2, ("opcode_crash")) ||
   strstr(a2, ("opcode_scan")) ||
   strstr(a2, ("vm_vap_ext")) || 
   strstr(a2, ("blur_exit")))
    {
        return 0;
    }
    else
    {
        return Sub_97794(a1, a2, a3);
    }
}

int (*ADITYA_FDFCC)(int a1, int a2);

int __fastcall DEVIL_FDFCC(int a1, int a2)
{
    return 0;
}

int sub_E6FF4(int a1, int a2)
{
 return 0;
}

int sub_EBB60(int a1, int a2)
{
 return 0;
}

int sub_16F110(int a1, int a2)
{
 return 0;
}

int (*osub_8E5F7)(int a1, unsigned char *a2, size_t a3);
int sub_8E5F7(int a1, unsigned char *a2, size_t a3)
{
    
       if (a3 == 0x52) { return 0; }  
       if (a3 == 0x62) { return 0; }
       if (a3 == 0x3A) { return 0; }
       if (a3 == 0x32) { return 0; }
       if (a3 == 0x56) { return 0; }
       if (a3 == 0x5E) { return 0; }
       if (a3 == 0x4E) { return 0; }
       
       return osub_8E5F7(a1,a2,a3);
}

int __fastcall sub_FA4A8(int a1, int a2)
{
  int v2; // r0
  int **v3; // r0
  int v4; // r0
  int v5; // r1
  _BYTE *v7; // [sp+8h] [bp-68h]
  _BYTE *v8; // [sp+Ch] [bp-64h]
  bool v9; // [sp+10h] [bp-60h]
  int *v10; // [sp+14h] [bp-5Ch]
  int v11; // [sp+1Ch] [bp-54h]
  int v14; // [sp+44h] [bp-2Ch]
  _DWORD v15[4]; // [sp+48h] [bp-28h] BYREF
  int v16; // [sp+58h] [bp-18h] BYREF
  int v17; // [sp+5Ch] [bp-14h] BYREF
  int v18[3]; // [sp+60h] [bp-10h] BYREF
  return v14;
}

int __fastcall sub_16D7C40(int a1)
{
  return 0;
}

size_t SKIN(const char *SkinLobby) {
    static const std::unordered_map<std::string, 
    std::string> SkinLobbyxuit = {
         {"403007","1405132"}
  ,{"403031","1405994"},
   {"403021","1405482"},
   {"403016","1406281"},
   {"403018","1405426"},
   {"403041","1405090"},
   {"403014","1405757"},
   {"403015","1400687"},
   {"202408001","202408009"},
   {"1908001","1908013"},
   {"2001001","2005025"},
   {"1903001","1903040"},
   {"401006","1402613"}
  };
    auto it = SkinLobbyxuit.find(SkinLobby);
    if (it != SkinLobbyxuit.end()) {
    strcpy((char *)SkinLobby, it->second.c_str());
    }
    
    return strlen(SkinLobby);
}

void *anort_thread(void *) {
while (!isLibraryLoaded(OBFUSCATE("libanort.so")))
    {
        sleep(1);
    }
	
//HOOK_LIB("libanort.so","0xA060E",hsub_A060E,osub_A060E);


   return NULL;
}


void *ue4_thread(void *) {
while (!isLibraryLoaded(OBFUSCATE("libUE4.so")))
    {
        sleep(1);
    }
HOOK_LIB_NO_ORIG("libUE4.so", "0x8D0190", SKIN);
PATCH_LIB("libUE4.so", "0x1639298", "00 00 00 00");
HOOK_LIB_NO_ORIG("libUE4.so", "0x16D7C40",sub_16D7C40); //TERMINATION 


   return NULL;
}



void *gcloud_thread(void *) {
while (!isLibraryLoaded(OBFUSCATE("libgcloud.so")))
    {
        sleep(1);
    }
	

 



	



   return NULL;
}

void *anogs_thread(void *) {
while (!isLibraryLoaded(OBFUSCATE("libanogs.so")))
    {
        sleep(1);
    }
PATCH_LIB("libanogs.so", "0xacad2", "00 20 70 47");
PATCH_LIB("libanogs.so", "0x8E5F6", "00 20 70 47");
PATCH_LIB("libanogs.so", "0x260D00", "00 20 70 47");
LOGI(OBFUSCATE("ALFAS POWER"));






 return NULL;
}


__attribute__((constructor))
void lib_main() {

{
  	
    pthread_t ptid;
	pthread_t ptid1;
    pthread_create(&ptid, NULL, anogs_thread, NULL);
    pthread_create(&ptid, NULL, ue4_thread, NULL);
  //  pthread_create(&ptid, NULL, bypass_thread, NULL);
    
    
}
}
