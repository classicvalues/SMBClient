/*
 * Copyright (c) 2017 - 2018 Apple Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * URL1 - used for tests that only need a single user connection to server
 * URL2 - used for multi user testing to the same server
 * URL3 - used for tests that only test SMBv1
 */


#ifndef FAKE_XC_TEST
    #import <XCTest/XCTest.h>

    #if 0
        char g_test_url1[1024] = "smb://smbtest:storageSW0@127.0.0.1/SMBBasic";
        char g_test_url2[1024] = "smb://smbtest2:storageSW0@127.0.0.1/SMBBasic";
        char g_test_url3[1024] = "cifs://smbtest2:storageSW0@127.0.0.1/SMBBasic";
    #else
        #if 1
            char g_test_url1[1024] = "smb://Administrator:Password01!@192.168.1.30/SMBBasic";
            char g_test_url2[1024] = "smb://adbrad:Password01!@192.168.1.30/SMBBasic";
            char g_test_url3[1024] = "cifs://adbrad:Password01!@192.168.1.30/SMBBasic";
        #else
            char g_test_url1[1024] = "smb://ITAI-RAAB-PRL;nfs.lab.1:12345tgB@192.168.10.3/win_share_1";
            char g_test_url2[1024] = "smb://ITAI-RAAB-PRL;nfs.lab.2:12345tgB@192.168.10.3/win_share_1";
            char g_test_url3[1024] = "cifs://ITAI-RAAB-PRL;nfs.lab.2:12345tgB@192.168.10.3/win_share_1";
        #endif
    #endif
#else
    /* BATS support */
    #import "FakeXCTest.h"

    char g_test_url1[1024] = {0};
    char g_test_url2[1024] = {0};
    char g_test_url3[1024] = {0};
#endif

#include <CoreFoundation/CoreFoundation.h>
#include <smbclient/smbclient.h>
#include <smbclient/smbclient_netfs.h>
#include <NetFS/NetFS.h>
#include <SystemConfiguration/SystemConfiguration.h>

#include "netshareenum.h"
#include "smb_lib.h"
#include "parse_url.h"
#include "upi_mbuf.h"
#include "mchain.h"
#include "rq.h"
#include "smb_converter.h"
#include "ntstatus.h"
#include "smbclient_internal.h"
#include "LsarLookup.h"
#include <smbclient/netbios.h>

#include <stdio.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/attr.h>
#include <sys/vnode.h>
#include <sys/xattr.h>
#include <dirent.h>

char default_test_filename[] = "testfile";

static const char* ROOT_LONG_NAME_PREFIX = "PR";
static const char* TEST_LONG_NAME_PREFIX = "PT";

static uint32_t sNextTestDirectoryIndex = 0;

char root_test_dir[PATH_MAX];
char cur_test_dir[PATH_MAX];

int gVerbose = 1;
int gInitialized = 0;

/* URLRefs to do the mounts with */
CFURLRef urlRef1 = NULL;
CFURLRef urlRef2 = NULL;
CFURLRef urlRef3 = NULL;

/* Data for UBC Cache tests */
const char data1[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
const char data2[] = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz0123456789";
const char data3[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+2";



@interface SMBClientBasicFunctionalTests : XCTestCase

@end


@implementation SMBClientBasicFunctionalTests

- (void)setUp {
    char buffer[PATH_MAX];
    const char *url1, *url2, *url3;
    CFStringRef urlStringRef1 = NULL;
    CFStringRef urlStringRef2 = NULL;
    CFStringRef urlStringRef3 = NULL;

    // Put setup code here. This method is called before the invocation of each test method in the class.

    [super setUp];

    if (gInitialized == 0) {
        /* Only do once */
        gInitialized = 1;

        /* Create root test dir name */
        sprintf(root_test_dir, "%s_%08lX_%08X",
                ROOT_LONG_NAME_PREFIX, time(NULL), getpid());
    }

    /* Create test dir name inside of root dir */
    sprintf(buffer, "%s_%010lu", TEST_LONG_NAME_PREFIX,
            (long unsigned)sNextTestDirectoryIndex++);
    strlcpy(cur_test_dir, root_test_dir, sizeof(cur_test_dir));
    strlcat(cur_test_dir, "/", sizeof(cur_test_dir));
    strlcat(cur_test_dir, buffer, sizeof(cur_test_dir));


    url1 = g_test_url1;
    url2 = g_test_url2;
    url3 = g_test_url3;

    /* Convert char* to a CFString */
    urlStringRef1 = CFStringCreateWithCString(kCFAllocatorDefault, url1, kCFStringEncodingUTF8);
    if (urlStringRef1 == NULL) {
        XCTFail("CFStringCreateWithCString failed with <%s> \n", url1);
        return;
    }

    /* Convert CFStrings to CFURLRefs */
    urlRef1 = CFURLCreateWithString (NULL, urlStringRef1, NULL);
    CFRelease(urlStringRef1);
    if (urlRef1 == NULL) {
        XCTFail("CFURLCreateWithString failed with <%s> \n", url1);
        return;
    }

    /* Convert char* to a CFString */
    urlStringRef2 = CFStringCreateWithCString(kCFAllocatorDefault, url2, kCFStringEncodingUTF8);
    if (urlStringRef2 == NULL) {
        XCTFail("CFStringCreateWithCString failed with <%s> \n", url2);
        CFRelease(urlRef1);
        return;
    }

    /* Convert CFStrings to CFURLRefs */
    urlRef2 = CFURLCreateWithString (NULL, urlStringRef2, NULL);
    CFRelease(urlStringRef2);
    if (urlRef2 == NULL) {
        XCTFail("CFURLCreateWithString failed with <%s> \n", url2);
        CFRelease(urlRef1);
        return;
    }

    /* Convert char* to a CFString */
    urlStringRef3 = CFStringCreateWithCString(kCFAllocatorDefault, url3, kCFStringEncodingUTF8);
    if (urlStringRef3 == NULL) {
        XCTFail("CFStringCreateWithCString failed with <%s> \n", url3);
        CFRelease(urlRef1);
        CFRelease(urlRef2);
        return;
    }

    /* Convert CFStrings to CFURLRefs */
    urlRef3 = CFURLCreateWithString (NULL, urlStringRef3, NULL);
    CFRelease(urlStringRef3);
    if (urlRef3 == NULL) {
        XCTFail("CFURLCreateWithString failed with <%s> \n", url3);
        CFRelease(urlRef1);
        CFRelease(urlRef2);
        return;
    }
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.

    if (urlRef1) {
        CFRelease(urlRef1);
    }

    if (urlRef2) {
        CFRelease(urlRef2);
    }

    if (urlRef3) {
        CFRelease(urlRef3);
    }
}

int do_create_test_dirs(const char *mp) {
    int error = 0;
    char dir_path[PATH_MAX];

    /* Set up path on mp to root dir */
    strlcpy(dir_path, mp, sizeof(dir_path));
    strlcat(dir_path, "/", sizeof(dir_path));
    strlcat(dir_path, root_test_dir, sizeof(dir_path));

    /* Create root test dir, ok for this dir to already exist */
    error = mkdir(dir_path, S_IRWXU);
    if ((error) && (errno != EEXIST)) {
        fprintf(stderr, "mkdir on <%s> failed %d:%s \n",
                dir_path, errno, strerror(errno));
        error = errno;
        goto done;
    }

    /* Make sure the dir is read/write */
    error = chmod(dir_path, S_IRWXU | S_IRWXG | S_IRWXO);
    if (error) {
        fprintf(stderr, "chmod on <%s> failed %d:%s \n",
                dir_path, errno, strerror(errno));
        error = errno;
        goto done;
    }

    /* Create test dir */
    strlcpy(dir_path, mp, sizeof(dir_path));
    strlcat(dir_path, "/", sizeof(dir_path));
    strlcat(dir_path, cur_test_dir, sizeof(dir_path));

    error = mkdir(dir_path, S_IRWXU);
    if (error) {
        fprintf(stderr, "mkdir on <%s> failed %d:%s \n",
                dir_path, errno, strerror(errno));
        error = errno;
        goto done;
    }

    /* Make sure the dir is read/write */
    error = chmod(dir_path, S_IRWXU | S_IRWXG | S_IRWXO);
    if (error) {
        fprintf(stderr, "chmod on <%s> failed %d:%s \n",
                dir_path, errno, strerror(errno));
        error = errno;
        goto done;
    }

    printf("Test dir <%s> \n", dir_path);

done:
    return(error);
}

int do_delete_test_dirs(const char *mp) {
    int error = 0;
    char dir_path[PATH_MAX];

    /* Set up path on mp to test dir */
    strlcpy(dir_path, mp, sizeof(dir_path));
    strlcat(dir_path, "/", sizeof(dir_path));
    strlcat(dir_path, cur_test_dir, sizeof(dir_path));

    /* Do the Delete on test dir */
    error = rmdir(dir_path);
    if (error) {
        fprintf(stderr, "do_delete on <%s> failed <%s (%d)> \n",
                dir_path, strerror(errno), errno);
        error = errno;
        goto done;
    }

    /* Set up path on mp to root dir */
    strlcpy(dir_path, mp, sizeof(dir_path));
    strlcat(dir_path, "/", sizeof(dir_path));
    strlcat(dir_path, root_test_dir, sizeof(dir_path));

    /* Do the Delete on root dir */
    error = rmdir(dir_path);
    if (error) {
        fprintf(stderr, "do_delete on <%s> failed <%s (%d)> \n",
                dir_path, strerror(errno), errno);
        error = errno;
        return(error);
    }

done:
    return(error);
}

static void do_create_mount_path(char *mp, size_t mp_len, const char *test_name)
{
    UInt8 uuid[16] = {0};
    uuid_generate(uuid);
    
    snprintf(mp, mp_len, "/private/tmp/%s_%x%x%x%x-%x%x-%x%x-%x%x-%x%x%x%x%x%x",
             test_name,
             uuid[0], uuid[1], uuid[2], uuid[3],
             uuid[4], uuid[5],
             uuid[6], uuid[7],
             uuid[8], uuid[9],
             uuid[10], uuid[11], uuid[12], uuid[13], uuid[14], uuid[15]);
    printf("Created mountpoint: <%s> \n", mp);
}

static int do_mount(const char *mp, CFURLRef url, CFDictionaryRef openOptions, int mntflags)
{
    SMBHANDLE theConnection = NULL;
    CFStringRef mountPoint = NULL;
    CFDictionaryRef mountInfo = NULL;
    int error;
    CFNumberRef numRef = NULL;
    CFMutableDictionaryRef mountOptions = NULL;

    /* Make the dir to mount on */
    if ((mkdir(mp, S_IRWXU | S_IRWXG) == -1) && (errno != EEXIST)) {
        fprintf(stderr, "mkdir failed %d:%s for <%s>\n", errno, strerror(errno), mp);
        return errno;
    }

    /* Create the session ref */
    error = SMBNetFsCreateSessionRef(&theConnection);
    if (error) {
        fprintf(stderr, "SMBNetFsCreateSessionRef failed %d:%s for <%s>\n",
                error, strerror(error), mp);
        return error;
    }

    /* Attempt to log in to the server */
    error = SMBNetFsOpenSession(url, theConnection, openOptions, NULL);
    if (error) {
        fprintf(stderr, "SMBNetFsOpenSession failed %d:%s for <%s>\n",
                error, strerror(error), mp);
        (void)SMBNetFsCloseSession(theConnection);
        return error;
    }

    /* Create mount options dictionary */
    mountOptions = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!mountOptions) {
        fprintf(stderr, "CFDictionaryCreateMutable failed for <%s>\n", mp);
        (void)SMBNetFsCloseSession(theConnection);
        return error;
    }

    /*  Add mount flags into the mount options dictionary */
    numRef = CFNumberCreate( nil, kCFNumberIntType, &mntflags);
    if (numRef != NULL) {
        CFDictionarySetValue( mountOptions, kNetFSMountFlagsKey, numRef);
        CFRelease(numRef);
    }

    /* Always force a new session even in the mount */
    CFDictionarySetValue(mountOptions, kNetFSForceNewSessionKey, kCFBooleanTrue);

    /* Convert mount point into a CFStringRef */
    mountPoint = CFStringCreateWithCString(kCFAllocatorDefault, mp, kCFStringEncodingUTF8);
    if (mountPoint) {
        /* Attempt the mount */
        error = SMBNetFsMount(theConnection, url, mountPoint, mountOptions, &mountInfo, NULL, NULL);
        if (error) {
            fprintf(stderr, "SMBNetFsMount failed %d:%s for <%s>\n",
                    error, strerror(error), mp);
            /* Continue on to clean up */
        }

        CFRelease(mountPoint);
        if (mountInfo) {
            CFRelease(mountInfo);
        }
    }
    else {
        fprintf(stderr, "CFStringCreateWithCString failed for <%s>\n", mp);
        error = ENOMEM;
    }

    CFRelease(mountOptions);
    (void)SMBNetFsCloseSession(theConnection);

    return error;
}

int mount_two_sessions(const char *mp1, const char *mp2, int useSMB1)
{
    int error = 0;

    CFMutableDictionaryRef openOptions = NULL;

    /* We want to force new sessions for each mount */
    openOptions = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (openOptions == NULL) {
        error = ENOMEM;
        goto done;
    }
    CFDictionarySetValue(openOptions, kNetFSForceNewSessionKey, kCFBooleanTrue);

    /*
     * Mount are done with MNT_DONTBROWSE so that Finder does not see them
     *
     * We will need two mounts to start with
     */
    if (useSMB1 == 0) {
        /* Use SMB 2/3 */
        error = do_mount(mp1, urlRef1, openOptions, MNT_DONTBROWSE);
    }
    else {
        /* Force using SMB 1 */
        error = do_mount(mp1, urlRef3, openOptions, MNT_DONTBROWSE);
    }
    if (error) {
        fprintf(stderr, "do_mount failed for first url %d\n", error);
        goto done;
    }

    /* Do they want a second mount \? */
    if (mp2 != NULL) {
        error = do_mount(mp2, urlRef2, openOptions, MNT_DONTBROWSE);
        if (error) {
            fprintf(stderr, "do_mount failed for second url %d\n", error);
            goto done;
        }
    }

done:
    if (openOptions) {
        CFRelease(openOptions);
    }

    return (error);
}

int setup_file_paths(const char *mp1, const char *mp2,
                     const char *filename,
                     char *file_path1, size_t file_len1,
                     char *file_path2, size_t file_len2)
{
    int error = 0;
    int fd1 = -1;

    /* Set up file paths on both mounts */
    strlcpy(file_path1, mp1, file_len1);
    strlcat(file_path1, "/", file_len1);
    strlcat(file_path1, cur_test_dir, file_len1);
    strlcat(file_path1, "/", file_len1);
    strlcat(file_path1, filename, file_len1);

    strlcpy(file_path2, mp2,file_len2);
    strlcat(file_path2, "/",file_len2);
    strlcat(file_path2, cur_test_dir,file_len2);
    strlcat(file_path2, "/",file_len2);
    strlcat(file_path2, filename,file_len2);

    /* Create the test dirs */
    error = do_create_test_dirs(mp1);
    if (error) {
        fprintf(stderr, "do_create_test_dirs on <%s> failed %d:%s \n", mp1,
                error, strerror(error));
        goto done;
    }

    /*
     * Open the file for the writer on mp1
     * If file exists, open it and truncate it
     * If file does not exist, create it
     *
     * Note umask prevents me from also allowing RWX to group/other so
     * have to do an extra call to set those permissions
     */
    fd1 = open(file_path1, O_RDWR | O_CREAT | O_TRUNC, S_IRWXU);
    if (fd1 == -1) {
        fprintf(stderr, "open on <%s> failed %d:%s \n", file_path1,
                errno,strerror(errno));
        error = errno;
        goto done;
    }

    /* smbx time granularity is 1 second so wait after each write/truncate */
    sleep(1);

    /* Make sure the file is read/write */
    error = chmod(file_path1, S_IRWXU | S_IRWXG | S_IRWXO);
    if (error) {
        fprintf(stderr, "chmod on <%s> failed %d:%s \n", file_path1,
                error, strerror(error));
        goto done;
    }

done:
    if (fd1 != -1) {
        /* Close file on mp1 */
        error = close(fd1);
        if (error) {
            fprintf(stderr, "close on fd1 failed %d:%s \n", error, strerror(error));
            goto done;
        }
    }

    return(error);
}

int read_and_verify(int fd, const char *data, size_t data_len)
{
    int error = 0;
    ssize_t read_size;
    char *read_buffer;
    size_t read_buf_len = data_len * 2;
    int i;
    char *cptr;

    /* Read and Verify the data */
    read_buffer = malloc(read_buf_len);
    if (read_buffer == NULL) {
        fprintf(stderr, "malloc failed for read buffer \n");
        error = ENOMEM;
        goto done;
    }
    bzero(read_buffer, read_buf_len);

    read_size = pread(fd, read_buffer, read_buf_len, 0);
    if (read_size != data_len) {
        fprintf(stderr, "read verify failed %zd != %zd \n", read_size, data_len);
        error = EINVAL;
        goto done;
    }

    if (memcmp(data, read_buffer, data_len)) {
        fprintf(stderr, "memcmp failed \n");
        
        fprintf(stderr, "Correct data \n");
        cptr = (char *) data;
        for (i = 0; i < data_len; i++) {
            fprintf(stderr, "%c (0x%x) ", *cptr, *cptr);
            cptr++;
        }
        fprintf(stderr, "\n");

        fprintf(stderr, "Read data \n");
        cptr = read_buffer;
        for (i = 0; i < data_len; i++) {
            fprintf(stderr, "%c (0x%x) ", *cptr, *cptr);
            cptr++;
        }
        fprintf(stderr, "\n");
        
        error = EINVAL;
        goto done;
    }

done:
    return (error);
}

int write_and_verify(int fd, const char *data, size_t data_len)
{
    int error = 0;
    ssize_t write_size;

    /* Write out data */
    write_size = pwrite(fd, data, data_len, 0);
    if (write_size != data_len) {
        fprintf(stderr, "data write failed %zd != %zd \n",  write_size, data_len);
        error = EINVAL;
        goto done;
    }

    error = read_and_verify(fd, data, data_len);
    if (error) {
        goto done;
    }

done:
    return (error);
}

static int do_GetServerInfo(CFURLRef url,
                            SMBHANDLE inConnection,
                            CFDictionaryRef openOptions,
                            CFDictionaryRef *serverParms)
{
    int error;

    if ((inConnection == NULL) || (url == NULL)) {
        fprintf(stderr, "inConnection or url is null \n");
        return EINVAL;
    }
    
    error = SMBNetFsGetServerInfo(url, inConnection, openOptions, serverParms);
    if (error) {
        fprintf(stderr, "SMBNetFsGetServerInfo failed %d:%s \n",
                error, strerror(error));
        return error;
    }
    
    return error;
}

static int do_OpenSession(CFURLRef url,
                          SMBHANDLE inConnection,
                          CFDictionaryRef openOptions,
                          CFDictionaryRef *sessionInfo)
{
    int error;
    
    if ((inConnection == NULL) || (url == NULL)) {
        fprintf(stderr, "inConnection or url is null \n");
        return EINVAL;
    }
    
    error = SMBNetFsOpenSession(url, inConnection, openOptions, sessionInfo);
    if (error) {
        fprintf(stderr, "SMBNetFsOpenSession failed %d:%s \n",
                error, strerror(error));
        return error;
    }
    
    return error;
}

static int do_CloseSession(SMBHANDLE inConnection)
{
    int error;
    
    if (inConnection == NULL) {
        fprintf(stderr, "inConnection is null \n");
        return EINVAL;
    }
    
    error = SMBNetFsCloseSession(inConnection);
    if (error) {
        fprintf(stderr, "SMBNetFsCloseSession failed %d:%s \n",
                error, strerror(error));
        return error;
    }
    
    return error;
}

static int do_EnumerateShares(SMBHANDLE inConnection,
                              CFDictionaryRef *sharePoints)
{
    int error;
    
    if (inConnection == NULL) {
        fprintf(stderr, "inConnection is null \n");
        return EINVAL;
    }
    
    error = smb_netshareenum(inConnection, sharePoints, TRUE);
    if (error) {
        fprintf(stderr, "smb_netshareenum failed %d:%s \n",
               error, strerror(error));
        return error;
    }
    
    return error;
}

/*
 * testUBCOpenWriteClose - Verify that open/close invalidates UBC
 *
 * 1.   Open testfile on mount 1, write data, read/verify data, close file
 *      Open testfile on mount 2, read/verify data, close file
 * 2.   Open testfile on mount 1, change data but not length, read/verify data, close file
 *      Open testfile on mount 2, read/verify data, close file
 * 3.   Open testfile on mount 1, change data including length, read/verify data, close file
 *      Open testfile on mount 2, read/verify data, close file
 */
- (void)testUBCOpenWriteClose
{
    int error = 0;
    char file_path1[PATH_MAX];
    char file_path2[PATH_MAX];
    int fd1 = -1, fd2 = -1;
    int mode1 = O_RDWR;
    int mode2 = O_RDONLY;
    int iteration = 0;
    char mp1[PATH_MAX];
    char mp2[PATH_MAX];

    /*
     * We will need two mounts to start with
     */
    do_create_mount_path(mp1, sizeof(mp1), "testUBCOpenWriteCloseMp1");
    do_create_mount_path(mp2, sizeof(mp2), "testUBCOpenWriteCloseMp2");
    
    error = mount_two_sessions(mp1, mp2, 0);
    if (error) {
        XCTFail("mount_two_sessions failed %d \n", error);
        goto done;
    }

again:

    /* Set up file paths on both mounts and create test file */
    error = setup_file_paths(mp1, mp2, default_test_filename,
                             file_path1, sizeof(file_path1),
                             file_path2, sizeof(file_path2));
    if (error) {
        XCTFail("setup_file_paths failed %d \n", error);
        goto done;
    }

    if (iteration == 1) {
        printf("Repeat tests with O_SHLOCK \n");
        mode1 |= O_SHLOCK;
        mode2 |= O_SHLOCK;
    }

    /*
     * Open the file for the writer on mp1
     */
    fd1 = open(file_path1, mode1);
    if (fd1 == -1) {
        XCTFail("open on <%s> failed %d:%s \n", file_path1,
                errno, strerror(errno));
        goto done;
    }

    /* Write out and verify initial data on mp1 */
    error = write_and_verify(fd1, data1, sizeof(data1));
    if (error) {
        XCTFail("initial write_and_verify failed %d \n", error);
        goto done;
    }

    /* Close file on mp1 which should write the data out to the server */
    error = close(fd1);
    if (error) {
        XCTFail("close on fd1 failed %d:%s \n",
                error, strerror(error));
        goto done;
    }
    else {
        fd1 = -1;
    }

    /* smbx time granularity is 1 second so wait after each write/truncate */
    sleep(1);

    /* Switch to second connection, mp2 and open the file */
    fd2 = open(file_path2, mode2);
    if (fd2 == -1) {
        XCTFail("open on <%s> failed %d:%s \n",
                file_path2, errno, strerror(errno));
        goto done;
    }

    /* Read and verify initial data on mp2 */
    error = read_and_verify(fd2, data1, sizeof(data1));
    if (error) {
        XCTFail("initial read_and_verify failed %d:%s \n",
                error, strerror(error));
        goto done;
    }

    /* Close file on mp2 */
    error = close(fd2);
    if (error) {
        XCTFail("close on fd2 failed %d:%s \n",
                error, strerror(error));
        goto done;
    }
    else {
        fd2 = -1;
    }

    printf("Initial data passes \n");


    /*
     * Open the file again on mp1 and change the data but not data len
     */
    fd1 = open(file_path1, mode1);
    if (fd1 == -1) {
        XCTFail("open on <%s> failed %d:%s \n",
                file_path1, errno, strerror(errno));
        goto done;
    }

    /* Write out and verify new data, but same length */
    error = write_and_verify(fd1, data2, sizeof(data2));
    if (error) {
        XCTFail("second write_and_verify failed %d \n", error);
        goto done;
    }

    /* Close file on mp1 which should write the data out to the server */
    error = close(fd1);
    if (error) {
        XCTFail("close on fd1 failed %d:%s \n",
                error, strerror(error));
        goto done;
    }
    else {
        fd1 = -1;
    }

    /* smbx time granularity is 1 second so wait after each write/truncate */
    sleep(1);

    /* Switch to second connection, mp2 and open the file */
    fd2 = open(file_path2, mode2);
    if (fd2 == -1) {
        XCTFail("open on <%s> failed %d:%s \n",
                file_path2, errno, strerror(errno));
        goto done;
    }

    /* Read data into UBC and verify the second data */
    error = read_and_verify(fd2, data2, sizeof(data2));
    if (error) {
        XCTFail("second read_and_verify failed %d:%s \n",
                error, strerror(error));
        goto done;
    }

    /* Close file on mp2 */
    error = close(fd2);
    if (error) {
        XCTFail("close on fd2 failed %d:%s \n",
                error, strerror(error));
        goto done;
    }
    else {
        fd2 = -1;
    }

    printf("Change data but NOT length passes \n");


    /*
     * Open the file again on mp1 and change the data and data len
     */
    fd1 = open(file_path1, mode1);
    if (fd1 == -1) {
        XCTFail("open on <%s> failed %d:%s \n",
                file_path1, errno, strerror(errno));
        goto done;
    }

    /* Write out new data, but different length */
    error = write_and_verify(fd1, data3, sizeof(data3));
    if (error) {
        XCTFail("third write_and_verify failed %d \n", error);
        goto done;
    }

    /* Close file on mp1 which should write the data out to the server */
    error = close(fd1);
    if (error) {
        XCTFail("close on fd1 failed %d:%s \n",
                error, strerror(error));
        goto done;
    }
    else {
        fd1 = -1;
    }

    /* smbx time granularity is 1 second so wait after each write/truncate */
    sleep(1);

    /* Switch to second connection, mp2 and open the file */
    fd2 = open(file_path2, mode2);
    if (fd2 == -1) {
        XCTFail("open on <%s> failed %d:%s \n",
                file_path2, errno, strerror(errno));
        goto done;
    }

    /* Read data into UBC and verify the third data */
    error = read_and_verify(fd2, data3, sizeof(data3));
    if (error) {
        XCTFail("third read_and_verify failed %d:%s \n",
                error, strerror(error));
        goto done;
    }

    /* Close file on mp2 */
    error = close(fd2);
    if (error) {
        XCTFail("close on fd2 failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        fd2 = -1;
    }

    printf("Change data AND length passes \n");

    /* Do the Delete on test file */
    error = remove(file_path1);
    if (error) {
        fprintf(stderr, "do_delete on <%s> failed <%s (%d)>",
                file_path1, strerror(errno), errno);
        goto done;
    }

    /*
     * If no errors, attempt to delete test dirs. This could fail if a
     * previous test failed and thats fine.
     */
    do_delete_test_dirs(mp1);

    if (iteration == 0) {
        iteration += 1;
        goto again;
    }

done:
    if (fd1 != -1) {
        /* Close file on mp1 */
        error = close(fd1);
        if (error) {
            XCTFail("close on fd1 failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (fd2 != -1) {
        /* Close file on mp2 */
        error = close(fd2);
        if (error) {
            XCTFail("close on fd2 failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("unmount failed for first url %d\n", errno);
    }

    if (unmount(mp2, MNT_FORCE) == -1) {
        XCTFail("unmount failed for second url %d\n", errno);
    }

    rmdir(mp1);
    rmdir(mp2);
}

/*
 * testUBCOpenWriteFsyncClose - Verify that open/write/fsync pushes data to
 *      server while leaving file open on mp1, but open/close file on mp2
 *
 * 1.   Open testfile on mount 1, write data, read/verify data, fsync data
 *      Open testfile on mount 2, read/verify data, close file
 * 2.   On mount 1, change data but not length, read/verify data, fsync data
 *      Open testfile on mount 2, read/verify data, close file
 * 3.   On mount 1, change data including length, read/verify data, fsync data
 *      Open testfile on mount 2, read/verify data, close file
 * 4.   Close testfile on mount 1
 */
- (void)testUBCOpenWriteFsyncClose
{
    int error = 0;
    char file_path1[PATH_MAX];
    char file_path2[PATH_MAX];
    int fd1 = -1, fd2 = -1;
    char mp1[PATH_MAX];
    char mp2[PATH_MAX];

    /*
     * We will need two mounts to start with
     */
    do_create_mount_path(mp1, sizeof(mp1), "testUBCOpenWriteFsyncCloseMp1");
    do_create_mount_path(mp2, sizeof(mp2), "testUBCOpenWriteFsyncCloseMp2");

    error = mount_two_sessions(mp1, mp2, 0);
    if (error) {
        XCTFail("mount_two_sessions failed %d \n", error);
        goto done;
    }

    /* Set up file paths on both mounts and create test file */
    error = setup_file_paths(mp1, mp2, default_test_filename,
                             file_path1, sizeof(file_path1),
                             file_path2, sizeof(file_path2));
    if (error) {
        XCTFail("setup_file_paths failed %d \n", error);
        goto done;
    }

    /*
     * Open the file for the writer on mp1
     */
    fd1 = open(file_path1, O_RDWR);
    if (fd1 == -1) {
        XCTFail("open on <%s> failed %d:%s \n", file_path1,
                errno, strerror(errno));
        goto done;
    }

    /* Write out and verify initial data on mp1 */
    error = write_and_verify(fd1, data1, sizeof(data1));
    if (error) {
        XCTFail("initial write_and_verify failed %d \n", error);
        goto done;
    }

    /* Call fsync on mp1 which should write the data out to the server */
    error = fsync(fd1);
    if (error) {
        XCTFail("fsync on fd1 failed %d:%s \n", error, strerror(error));
        goto done;
    }

    /* smbx time granularity is 1 second so wait after each write/truncate */
    sleep(1);

    /* Switch to second connection, mp2 and open the file */
    fd2 = open(file_path2, O_RDWR);
    if (fd2 == -1) {
        XCTFail("open on <%s> failed %d:%s \n",
                file_path2, errno, strerror(errno));
        goto done;
    }

    /* Read data into UBC and verify the initial data */
    error = read_and_verify(fd2, data1, sizeof(data1));
    if (error) {
        XCTFail("initial read_and_verify failed %d:%s \n", error, strerror(error));
        goto done;
    }

    /* Close file on mp2 */
    error = close(fd2);
    if (error) {
        XCTFail("close on fd2 failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        fd2 = -1;
    }

    printf("Initial data passes \n");


    /*
     * File on mp1 is still open. Change the data but not data len
     */

    /* Write out and verify new data, but same length */
    error = write_and_verify(fd1, data2, sizeof(data2));
    if (error) {
        XCTFail("second write_and_verify failed %d \n", error);
        goto done;
    }

    /* Call fsync on mp1 which should write the data out to the server */
    error = fsync(fd1);
    if (error) {
        XCTFail("fsync on fd1 failed %d:%s \n", error, strerror(error));
        goto done;
    }

    /* smbx time granularity is 1 second so wait after each write/truncate */
    sleep(1);

    /* Switch to second connection, mp2 and open the file */
    fd2 = open(file_path2, O_RDWR);
    if (fd2 == -1) {
        XCTFail("open on <%s> failed %d:%s \n", file_path2, errno, strerror(errno));
        goto done;
    }

    /* Read data into UBC and verify the second data */
    error = read_and_verify(fd2, data2, sizeof(data2));
    if (error) {
        XCTFail("second read_and_verify failed %d:%s \n",
                error, strerror(error));
        goto done;
    }

    /* Close file on mp2 */
    error = close(fd2);
    if (error) {
        XCTFail("close on fd2 failed %d:%s \n",
                error, strerror(error));
        goto done;
    }
    else {
        fd2 = -1;
    }

    printf("Change data but NOT length passes \n");


    /*
     * File on mp1 is still open. Change the data and data len
     */

    /* Write out new data, but different length */
    error = write_and_verify(fd1, data3, sizeof(data3));
    if (error) {
        XCTFail("third write_and_verify failed %d \n", error);
        goto done;
    }

    /* Call fsync on mp1 which should write the data out to the server */
    error = fsync(fd1);
    if (error) {
        XCTFail("fsync on fd1 failed %d:%s \n", error, strerror(error));
        goto done;
    }

    /* smbx time granularity is 1 second so wait after each write/truncate */
    sleep(1);

    /* Switch to second connection, mp2 and open the file */
    fd2 = open(file_path2, O_RDWR);
    if (fd2 == -1) {
        XCTFail("open on <%s> failed %d:%s \n",
                file_path2, errno, strerror(errno));
        goto done;
    }

    /* Read data into UBC and verify the third data */
    error = read_and_verify(fd2, data3, sizeof(data3));
    if (error) {
        XCTFail("third read_and_verify failed %d:%s \n",
                error, strerror(error));
        goto done;
    }

    /* Close file on mp2 */
    error = close(fd2);
    if (error) {
        XCTFail("close on fd2 failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        fd2 = -1;
    }

    printf("Change data AND length passes \n");

    /* Close file on mp1 */
    error = close(fd1);
    if (error) {
        XCTFail("close on fd1 failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        fd1 = -1;
    }

    /* Do the Delete on test file */
    error = remove(file_path1);
    if (error) {
        fprintf(stderr, "do_delete on <%s> failed <%s (%d)>",
                file_path1, strerror(errno), errno);
        goto done;
    }

    /*
     * If no errors, attempt to delete test dirs. This could fail if a
     * previous test failed and thats fine.
     */
    do_delete_test_dirs(mp1);

done:
    if (fd1 != -1) {
        /* Close file on mp1 */
        error = close(fd1);
        if (error) {
            XCTFail("close on fd1 failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (fd2 != -1) {
        /* Close file on mp2 */
        error = close(fd2);
        if (error) {
            XCTFail("close on fd2 failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("unmount failed for first url %d\n", errno);
    }

    if (unmount(mp2, MNT_FORCE) == -1) {
        XCTFail("unmount failed for second url %d\n", errno);
    }

    rmdir(mp1);
    rmdir(mp2);
}


/*
 * testUBCOpenWriteFsync - Verify that open/write/fsync pushes data to server
 *                         even when the file is left open on mp1 and mp2
 *
 * 1.   Open testfile on mount 1, write data, read/verify data, fsync data
 *      Open testfile on mount 2, read/verify data
 * 2.   On mount 1, change data but not length, read/verify data, fsync data
 *      On mount 2, wait 5 seconds for meta data cache to expire, do fstat to
 *      get latest meta data, read/verify data
 * 3.   On mount 1, change data including length, read/verify data, fsync data
 *      On mount 2, wait 5 seconds for meta data cache to expire, do fstat to
 *      get latest meta data, read/verify data
 * 4.   Close testfile on mount 1. Close testfile on mount 2
 */
- (void)testUBCOpenWriteFsync
{
    int error = 0;
    char file_path1[PATH_MAX];
    char file_path2[PATH_MAX];
    int fd1 = -1, fd2 = -1;
    struct stat stat_buffer = {0};
    char mp1[PATH_MAX];
    char mp2[PATH_MAX];

    /*
     * We will need two mounts to start with
     */
    do_create_mount_path(mp1, sizeof(mp1), "testUBCOpenWriteFsyncMp1");
    do_create_mount_path(mp2, sizeof(mp2), "testUBCOpenWriteFsyncMp2");

    error = mount_two_sessions(mp1, mp2, 0);
    if (error) {
        XCTFail("mount_two_sessions failed %d \n", error);
        goto done;
    }

    /* Set up file paths on both mounts and create test file */
    error = setup_file_paths(mp1, mp2, default_test_filename,
                             file_path1, sizeof(file_path1),
                             file_path2, sizeof(file_path2));
    if (error) {
        XCTFail("setup_file_paths failed %d \n", error);
        goto done;
    }

    /*
     * Open the file for the writer on mp1
     */
    fd1 = open(file_path1, O_RDWR);
    if (fd1 == -1) {
        XCTFail("open on <%s> failed %d:%s \n", file_path1,
                errno, strerror(errno));
        goto done;
    }

    /* Write out and verify initial data on mp1 */
    error = write_and_verify(fd1, data1, sizeof(data1));
    if (error) {
        XCTFail("initial write_and_verify failed %d \n", error);
        goto done;
    }

    /* Call fsync on mp1 which should write the data out to the server */
    error = fsync(fd1);
    if (error) {
        XCTFail("fsync on fd1 failed %d:%s \n", error, strerror(error));
        goto done;
    }

    /* smbx time granularity is 1 second so wait after each write/truncate */
    sleep(1);

    /* Switch to second connection, mp2 and open the file */
    fd2 = open(file_path2, O_RDWR);
    if (fd2 == -1) {
        XCTFail("open on <%s> failed %d:%s \n",
                file_path2, errno, strerror(errno));
        goto done;
    }

    /* Read and verify initial data on mp2 */
    error = read_and_verify(fd2, data1, sizeof(data1));
    if (error) {
        XCTFail("initial read_and_verify failed %d:%s \n",
                error, strerror(error));
        goto done;
    }

    printf("Initial data passes \n");

    /*
     * File on mp1 is still open. Change the data but not data len
     */

    /* Write out and verify new data, but same length */
    error = write_and_verify(fd1, data2, sizeof(data2));
    if (error) {
        XCTFail("second write_and_verify failed %d \n", error);
        goto done;
    }

    /* Call fsync on mp1 which should write the data out to the server */
    error = fsync(fd1);
    if (error) {
        XCTFail("fsync on fd1 failed %d:%s \n", error, strerror(error));
        goto done;
    }

    /* smbx time granularity is 1 second so wait after each write/truncate */
    sleep(1);

    /* Switch to second connection, mp2 where the file is still open */

    /*
     * Sleep for at least 5 seconds to let meta data cache to expire.
     */
    sleep(5);

    /*
     * Reads get the vnode directly so need to force the meta data cache to
     * be checked by using fstat(). The meta data cache has expired by now
     * so fstat() will update the meta data cache where it should find
     * the modification data AND file size has changed and flush the UBC and
     * invalidate it.
     */
    error = fstat(fd2, &stat_buffer);
    if (error) {
        XCTFail("second fstat failed %d:%s \n",
                errno, strerror(errno));
        goto done;
    }

    /* Read data into UBC and verify the second data */
    error = read_and_verify(fd2, data2, sizeof(data2));
    if (error) {
        XCTFail("second read_and_verify failed %d:%s \n",
                error, strerror(error));
        goto done;
    }

    printf("Change data but NOT length passes \n");

    /*
     * File on mp1 is still open. Change the data and data len
     */

    /* Write out new data, but different length */
    error = write_and_verify(fd1, data3, sizeof(data3));
    if (error) {
        XCTFail("third write_and_verify failed %d \n", error);
        goto done;
    }

    /* Call fsync on mp1 which should write the data out to the server */
    error = fsync(fd1);
    if (error) {
        XCTFail("fsync on fd1 failed %d:%s \n", error, strerror(error));
        goto done;
    }

    /* smbx time granularity is 1 second so wait after each write/truncate */
    sleep(1);

    /* Switch to second connection, mp2 where the file is still open */

    /*
     * Sleep for at least 5 seconds to let meta data cache to expire.
     */
    sleep(5);

    /*
     * Reads get the vnode directly so need to force the meta data cache to
     * be checked by using fstat(). The meta data cache has expired by now
     * so fstat() will update the meta data cache where it should find
     * the modification data AND file size has changed and flush the UBC and
     * invalidate it.
     */
    error = fstat(fd2, &stat_buffer);
    if (error) {
        XCTFail("third fstat failed %d:%s \n",
                errno, strerror(errno));
        goto done;
    }

    /* Read data into UBC and verify the third data */
    error = read_and_verify(fd2, data3, sizeof(data3));
    if (error) {
        XCTFail("third read_and_verify failed %d:%s \n",
                error, strerror(error));
        goto done;
    }

    printf("Change data AND length passes \n");

    /* Close file on mp2 */
    error = close(fd2);
    if (error) {
        XCTFail("close on fd2 failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        fd2 = -1;
    }

    /* Close file on mp1 */
    error = close(fd1);
    if (error) {
        XCTFail("close on fd1 failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        fd1 = -1;
    }

    /* Do the Delete on test file */
    error = remove(file_path1);
    if (error) {
        fprintf(stderr, "do_delete on <%s> failed <%s (%d)>",
                file_path1, strerror(errno), errno);
        goto done;
    }

    /*
     * If no errors, attempt to delete test dirs. This could fail if a
     * previous test failed and thats fine.
     */
    do_delete_test_dirs(mp1);

done:
    if (fd1 != -1) {
        /* Close file on mp1 */
        error = close(fd1);
        if (error) {
            XCTFail("close on fd1 failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (fd2 != -1) {
        /* Close file on mp2 */
        error = close(fd2);
        if (error) {
            XCTFail("close on fd2 failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("unmount failed for first url %d\n", errno);
    }

    if (unmount(mp2, MNT_FORCE) == -1) {
        XCTFail("unmount failed for second url %d\n", errno);
    }

    rmdir(mp1);
    rmdir(mp2);
}

/*
 * testUBCOpenWriteNoCache - Verify that open/write with no cache pushes data to
 *      server immediately even when the file is left open on mp2
 *
 * 1.   Open testfile on mount 1, disable caching, write data, read/verify data
 *      Open testfile on mount 2, disable caching, read/verify data
 * 2.   On mount 1, change data but not length, read/verify data
 *      On mount 2, immediately read/verify data
 * 3.   On mount 1, change data including length, read/verify data
 *      On mount 2, immediately read/verify data
 * 4.   Close testfile on mount 1. Close testfile on mount 2
 */
-(void)testUBCOpenWriteNoCache
{
    int error = 0;
    char file_path1[PATH_MAX];
    char file_path2[PATH_MAX];
    int fd1 = -1, fd2 = -1;
    char mp1[PATH_MAX];
    char mp2[PATH_MAX];

    /*
     * We will need two mounts to start with
     */
    do_create_mount_path(mp1, sizeof(mp1), "testUBCOpenWriteNoCacheMp1");
    do_create_mount_path(mp2, sizeof(mp2), "testUBCOpenWriteNoCacheMp2");

    error = mount_two_sessions(mp1, mp2, 0);
    if (error) {
        XCTFail("mount_two_sessions failed %d \n", error);
        goto done;
    }

    /* Set up file paths on both mounts and create test file */
    error = setup_file_paths(mp1, mp2, default_test_filename,
                             file_path1, sizeof(file_path1),
                             file_path2, sizeof(file_path2));
    if (error) {
        XCTFail("setup_file_paths failed %d \n", error);
        goto done;
    }

    /*
     * Open the file for the writer on mp1
     */
    fd1 = open(file_path1, O_RDWR);
    if (fd1 == -1) {
        XCTFail("open on <%s> failed %d:%s \n", file_path1,
                errno, strerror(errno));
        goto done;
    }

    /* Turn off data caching. All IO should go out immediately */
    error = fcntl(fd1, F_NOCACHE, 1);
    if (error) {
        XCTFail("fcntl on fd1 failed %d:%s \n", error, strerror(error));
        goto done;
    }

    /* Write out and verify initial data on mp1 */
    error = write_and_verify(fd1, data1, sizeof(data1));
    if (error) {
        XCTFail("initial write_and_verify failed %d \n", error);
        goto done;
    }

    /* Switch to second connection, mp2 and open the file */
    fd2 = open(file_path2, O_RDWR);
    if (fd2 == -1) {
        XCTFail("open on <%s> failed %d:%s \n",
                file_path2, errno, strerror(errno));
        goto done;
    }

    /* Turn off data caching */
    error = fcntl(fd2, F_NOCACHE, 1);
    if (error) {
        XCTFail("fcntl on fd2 failed %d:%s \n", error, strerror(error));
        goto done;
    }

    /* Read and verify initial data on mp2 */
    error = read_and_verify(fd2, data1, sizeof(data1));
    if (error) {
        XCTFail("initial read_and_verify failed %d:%s \n",
                error, strerror(error));
        goto done;
    }

    printf("Initial data passes \n");

    /*
     * File on mp1 is still open. Change the data but not data len
     */

    /* Write out and verify new data, but same length */
    error = write_and_verify(fd1, data2, sizeof(data2));
    if (error) {
        XCTFail("second write_and_verify failed %d \n", error);
        goto done;
    }

    /* Switch to second connection, mp2 where the file is still open */

    /* Read data into UBC and verify the second data */
    error = read_and_verify(fd2, data2, sizeof(data2));
    if (error) {
        XCTFail("second read_and_verify failed %d:%s \n",
                error, strerror(error));
        goto done;
    }

    printf("Change data but NOT length passes \n");

    /*
     * File on mp1 is still open. Change the data and data len
     */

    /* Write out new data, but different length */
    error = write_and_verify(fd1, data3, sizeof(data3));
    if (error) {
        XCTFail("third write_and_verify failed %d \n", error);
        goto done;
    }

    /* Switch to second connection, mp2 where the file is still open */

    /* Read data into UBC and verify the third data */
    error = read_and_verify(fd2, data3, sizeof(data3));
    if (error) {
        XCTFail("third read_and_verify failed %d:%s \n",
                error, strerror(error));
        goto done;
    }

    printf("Change data AND length passes \n");

    /* Close file on mp2 */
    error = close(fd2);
    if (error) {
        XCTFail("close on fd2 failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        fd2 = -1;
    }

    /* Close file on mp1 */
    error = close(fd1);
    if (error) {
        XCTFail("close on fd1 failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        fd1 = -1;
    }

    /* Do the Delete on test file */
    error = remove(file_path1);
    if (error) {
        fprintf(stderr, "do_delete on <%s> failed <%s (%d)>",
                file_path1, strerror(errno), errno);
        goto done;
    }

    /*
     * If no errors, attempt to delete test dirs. This could fail if a
     * previous test failed and thats fine.
     */
    do_delete_test_dirs(mp1);

done:
    if (fd1 != -1) {
        /* Close file on mp1 */
        error = close(fd1);
        if (error) {
            XCTFail("close on fd1 failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (fd2 != -1) {
        /* Close file on mp2 */
        error = close(fd2);
        if (error) {
            XCTFail("close on fd2 failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("unmount failed for first url %d\n", errno);
    }

    if (unmount(mp2, MNT_FORCE) == -1) {
        XCTFail("unmount failed for second url %d\n", errno);
    }

    rmdir(mp1);
    rmdir(mp2);
}

/*
 * This test is only valid for servers that support AAPL create context and
 * support the NFS ACE for setting/getting Posix mode bits.
 */
-(void)testFileCreateInitialMode
{
    int error = 0;
    char file_path[PATH_MAX];
    int fd = -1;
    int oflag = O_EXCL | O_CREAT | O_SHLOCK | O_NONBLOCK | O_RDWR;
    int mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH; /* -rw-rw-rw- */
    struct stat stat_buffer = {0};
    int i;
    char mp1[PATH_MAX];

    /*
     * We will need just one mount to start with
     */
    do_create_mount_path(mp1, sizeof(mp1), "testFileCreateInitialModeMp1");

    error = mount_two_sessions(mp1, NULL, 0);
    if (error) {
        XCTFail("mount_two_sessions failed %d \n", error);
        goto done;
    }

    /* Create the test dirs */
    error = do_create_test_dirs(mp1);
    if (error) {
        XCTFail("do_create_test_dirs on <%s> failed %d:%s \n", mp1,
                error, strerror(error));
        goto done;
    }

    /* Set up file path */
    strlcpy(file_path, mp1, sizeof(file_path));
    strlcat(file_path, "/", sizeof(file_path));
    strlcat(file_path, cur_test_dir, sizeof(file_path));
    strlcat(file_path, "/", sizeof(file_path));
    strlcat(file_path, default_test_filename, sizeof(file_path));

    for (i = 0; i < 3; i++) {
        switch(i) {
            case 0:
                printf("Test with plain open \n");
                oflag = O_EXCL | O_CREAT | O_NONBLOCK | O_RDWR;
                break;
            case 1:
                printf("Test with O_SHLOCK \n");
                oflag = O_EXCL | O_CREAT | O_NONBLOCK | O_RDWR | O_SHLOCK;
                break;
            case 2:
                printf("Test with O_EXLOCK \n");
                oflag = O_EXCL | O_CREAT | O_NONBLOCK | O_RDWR | O_EXLOCK;
                break;
        }

        /*
         * Open the file for the writer on mp1
         */
        fd = open(file_path, oflag, mode);
        if (fd == -1) {
            XCTFail("open on <%s> failed %d:%s \n", file_path,
                    errno, strerror(errno));
            goto done;
        }

        error = fstat(fd, &stat_buffer);
        if (error) {
            XCTFail("fstat on <%s> failed %d:%s \n", file_path,
                    errno, strerror(errno));
            goto done;
        }

        /*
         * Note the umask will probably strip out write access so instead of
         * rw-rw-rw-, we end up with rw-r--r--
         */
        printf("Got initial mode <0o%o> \n", stat_buffer.st_mode);

        if ((stat_buffer.st_mode & ACCESSPERMS) == S_IRWXU) {
            /* Default mode, thus setting create mode must have failed */
            XCTFail("Initial create mode failed to set \n");
            goto done;
        }

        /* Close file */
        error = close(fd);
        if (error) {
            XCTFail("close on fd failed %d:%s \n", errno, strerror(errno));
            goto done;
        }
        else {
            fd = -1;
        }

        /* Do the Delete on test file */
        error = remove(file_path);
        if (error) {
            fprintf(stderr, "do_delete on <%s> failed <%s (%d)>",
                    file_path, strerror(errno), errno);
            goto done;
        }
    }


    /*
     * If no errors, attempt to delete test dirs. This could fail if a
     * previous test failed and thats fine.
     */
    do_delete_test_dirs(mp1);

done:
    if (fd != -1) {
        /* Close file on mp1 */
        error = close(fd);
        if (error) {
            XCTFail("close on fd failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("unmount failed for first url %d\n", errno);
    }

    rmdir(mp1);
}

/* Unit test for 42944162 which only occurs with SMB v1 */
-(void)testFileCreateSMBv1
{
    int error = 0;
    char file_path[PATH_MAX];
    int fd = -1;
    int oflag = O_EXCL | O_CREAT | O_RDWR;
    char mp1[PATH_MAX];

    /*
     * We will need just one mount to start with using SMB 1
     */
    do_create_mount_path(mp1, sizeof(mp1), "testFileCreateSMBv1Mp1");

    error = mount_two_sessions(mp1, NULL, 1);
    if (error) {
        XCTFail("mount_two_sessions failed %d \n", error);
        goto done;
    }

    /* Create the test dirs */
    error = do_create_test_dirs(mp1);
    if (error) {
        XCTFail("do_create_test_dirs on <%s> failed %d:%s \n", mp1,
                error, strerror(error));
        goto done;
    }

    /* Set up file path */
    strlcpy(file_path, mp1, sizeof(file_path));
    strlcat(file_path, "/", sizeof(file_path));
    strlcat(file_path, cur_test_dir, sizeof(file_path));
    strlcat(file_path, "/", sizeof(file_path));
    strlcat(file_path, default_test_filename, sizeof(file_path));

    /*
     * Open the file on mp1
     */
    fd = open(file_path, oflag, S_IRWXU | S_IRWXG | S_IRWXO);
    if (fd == -1) {
        XCTFail("open on <%s> failed %d:%s \n", file_path,
                errno, strerror(errno));
        goto done;
    }

    /* Close file */
    error = close(fd);
    if (error) {
        XCTFail("close on fd failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        fd = -1;
    }

    /* Do the Delete on test file */
    error = remove(file_path);
    if (error) {
        fprintf(stderr, "do_delete on <%s> failed <%s (%d)>",
                file_path, strerror(errno), errno);
        goto done;
    }

    /*
     * If no errors, attempt to delete test dirs. This could fail if a
     * previous test failed and thats fine.
     */
    do_delete_test_dirs(mp1);

done:
    if (fd != -1) {
        /* Close file on mp1 */
        error = close(fd);
        if (error) {
            XCTFail("close on fd failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("unmount failed for first url %d\n", errno);
    }

    rmdir(mp1);
}

-(void)testGetSrvrInfoPerf
{
    [self measureBlock:^{
        int error;
        SMBHANDLE theConnection = NULL;
        CFDictionaryRef serverParms = NULL;
        CFMutableDictionaryRef openOptions = NULL;
        
        /* We want to force new sessions for each mount */
        openOptions = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                &kCFTypeDictionaryKeyCallBacks,
                                                &kCFTypeDictionaryValueCallBacks);
        if (openOptions == NULL) {
            XCTFail("CFDictionaryCreateMutable failed for open options \n");
            goto done;
        }
        CFDictionarySetValue(openOptions, kNetFSForceNewSessionKey, kCFBooleanTrue);

        /* Create the session ref */
        error = SMBNetFsCreateSessionRef(&theConnection);
        if (error) {
            XCTFail("SMBNetFsCreateSessionRef failed %d:%s \n",
                    error, strerror(error));
            goto done;
        }
        
        error = do_GetServerInfo(urlRef1, theConnection,
                                 openOptions, &serverParms);
        if (error) {
            XCTFail("do_GetServerInfo failed %d:%s \n",
                    error, strerror(error));
            goto done;
        }
        
        error = do_CloseSession(theConnection);
        if (error) {
            XCTFail("do_CloseSession failed %d:%s \n",
                    error, strerror(error));
            goto done;
        }

    done:
        return;
    }];
}

-(void)testOpenSessionPerf
{
    [self measureBlock:^{
        int error;
        SMBHANDLE theConnection = NULL;
        CFDictionaryRef sessionInfo = NULL;
        CFMutableDictionaryRef openOptions = NULL;
        
        /* We want to force new sessions for each mount */
        openOptions = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                &kCFTypeDictionaryKeyCallBacks,
                                                &kCFTypeDictionaryValueCallBacks);
        if (openOptions == NULL) {
            XCTFail("CFDictionaryCreateMutable failed for open options \n");
            goto done;
        }
        CFDictionarySetValue(openOptions, kNetFSForceNewSessionKey, kCFBooleanTrue);
        
        /* Create the session ref */
        error = SMBNetFsCreateSessionRef(&theConnection);
        if (error) {
            XCTFail("SMBNetFsCreateSessionRef failed %d:%s \n",
                    error, strerror(error));
            goto done;
        }
        
        error = do_OpenSession(urlRef1, theConnection,
                               openOptions, &sessionInfo);
        if (error) {
            XCTFail("do_OpenSession failed %d:%s \n",
                    error, strerror(error));
            goto done;
        }
        
        error = do_CloseSession(theConnection);
        if (error) {
            XCTFail("do_CloseSession failed %d:%s \n",
                    error, strerror(error));
            goto done;
        }

    done:
        return;
    }];
}

/*
 * This test mimics what Finder does in Connect To and when checking an
 * already mounted server/share in the Finder Sidebar. These are the same
 * calls that the NetFS SMB Plugin uses
 */
-(void)testGetSrvrInfoEnumPerf
{
    [self measureBlock:^{
        int error;
        SMBHANDLE theConnection = NULL;
        CFDictionaryRef serverParms = NULL;
        CFDictionaryRef sessionInfo = NULL;
        CFDictionaryRef sharePoints = NULL;
        CFMutableDictionaryRef openOptions = NULL;
        
        /* We want to force new sessions for each mount */
        openOptions = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                &kCFTypeDictionaryKeyCallBacks,
                                                &kCFTypeDictionaryValueCallBacks);
        if (openOptions == NULL) {
            XCTFail("CFDictionaryCreateMutable failed for open options \n");
            goto done;
        }
        CFDictionarySetValue(openOptions, kNetFSForceNewSessionKey, kCFBooleanTrue);

        /* Create the session ref */
        error = SMBNetFsCreateSessionRef(&theConnection);
        if (error) {
            XCTFail("SMBNetFsCreateSessionRef failed %d:%s \n",
                    error, strerror(error));
            goto done;
        }
        
        error = do_GetServerInfo(urlRef1, theConnection,
                                 openOptions, &serverParms);
        if (error) {
            XCTFail("do_GetServerInfo failed %d:%s \n",
                    error, strerror(error));
            goto done;
        }
        
        error = do_OpenSession(urlRef1, theConnection,
                               openOptions, &sessionInfo);
        if (error) {
            XCTFail("do_OpenSession failed %d:%s \n",
                    error, strerror(error));
            goto done;
        }

        error = do_EnumerateShares(theConnection, &sharePoints);
        if (error) {
            XCTFail("do_EnumerateShares failed %d:%s \n",
                    error, strerror(error));
            goto done;
        }

        error = do_CloseSession(theConnection);
        if (error) {
            XCTFail("do_CloseSession failed %d:%s \n",
                    error, strerror(error));
            goto done;
        }

    done:
        return;
    }];
}

int createAttrList (struct attrlist *alist)
{
    memset(alist, 0, sizeof(struct attrlist));
    
    alist->bitmapcount = ATTR_BIT_MAP_COUNT;
    
    alist->commonattr = ATTR_CMN_NAME |
                        ATTR_CMN_DEVID |
                        ATTR_CMN_FSID |
                        ATTR_CMN_OBJTYPE |
                        ATTR_CMN_OBJTAG |
                        ATTR_CMN_OBJID |
                        ATTR_CMN_OBJPERMANENTID |
                        ATTR_CMN_PAROBJID |
                        ATTR_CMN_SCRIPT |
                        ATTR_CMN_CRTIME |
                        ATTR_CMN_MODTIME |
                        ATTR_CMN_CHGTIME |
                        ATTR_CMN_ACCTIME |
                        ATTR_CMN_BKUPTIME |
                        ATTR_CMN_FNDRINFO |
                        ATTR_CMN_OWNERID |
                        ATTR_CMN_GRPID |
                        ATTR_CMN_ACCESSMASK |
                        ATTR_CMN_FLAGS |
                        ATTR_CMN_USERACCESS |
                        ATTR_CMN_FILEID |
                        ATTR_CMN_PARENTID;
    
    alist->fileattr =   ATTR_FILE_LINKCOUNT |
                        ATTR_FILE_TOTALSIZE |
                        ATTR_FILE_ALLOCSIZE |
                        ATTR_FILE_IOBLOCKSIZE |
                        ATTR_FILE_DEVTYPE |
                        ATTR_FILE_DATALENGTH |
                        ATTR_FILE_DATAALLOCSIZE |
                        ATTR_FILE_RSRCLENGTH |
                        ATTR_FILE_RSRCALLOCSIZE;
    
    alist->dirattr =    ATTR_DIR_LINKCOUNT |
                        ATTR_DIR_ENTRYCOUNT |
                        ATTR_DIR_MOUNTSTATUS;
    
    alist->commonattr |=  ATTR_CMN_RETURNED_ATTRS;
        
    return 0;
}

int getAttrListBulk (int dirfd, int memSize, char *replyPtr,
                     attribute_set_t *requested_attributes)
{
    int returnCode = 0;
    struct attrlist alist;
    uint64_t bulkFlags = 0;

    returnCode = createAttrList(&alist);
    if (returnCode != 0) {
        fprintf(stderr, "Error in creating attribute list for getattrlistbulk. \n");
        return (-1);
    }
    
    memset(requested_attributes, 0, sizeof(attribute_set_t));
    requested_attributes->commonattr = alist.commonattr;
    requested_attributes->dirattr = alist.dirattr;
    requested_attributes->fileattr = alist.fileattr;
    
    bulkFlags |= FSOPT_NOFOLLOW;
    
//    if (gSetInvalOpt) {
//        bulkFlags |= FSOPT_PACK_INVAL_ATTRS;
//    }
    
    returnCode = getattrlistbulk(dirfd, &alist, replyPtr, memSize, bulkFlags);
    if (returnCode == -1) {
        fprintf(stderr, "getattrlistbulk failed %d (%s)\n",
                errno, strerror(errno));
        return  (-1);
    }
    
    if (returnCode != 0) {
        if (gVerbose) {
            printf("Number of Entries in Directory (Bulk): %d. \n", returnCode);
        }
    }
    
    return returnCode;
}

struct replyData {
    u_int32_t attr_length;
    attribute_set_t attrs_returned;
    char name[MAXPATHLEN];
    dev_t devid;
    fsid_t fsid;
    fsobj_type_t fsobj_type;
    fsobj_tag_t fsobj_tag;
    fsobj_id_t fsobj_id;
    fsobj_id_t fsobj_id_perm;
    fsobj_id_t fsobj_par_id;
    text_encoding_t script;
    struct timespec create_time;
    struct timespec mod_time;
    struct timespec change_time;
    struct timespec access_time;
    struct timespec backup_time;
    FileInfo finfo;
    FolderInfo folderInfo;
    ExtendedFileInfo exFinfo;
    ExtendedFolderInfo exFolderInfo;
    uid_t uid;
    gid_t gid;
    u_int32_t common_access;
    uint32_t common_flags;
    uint32_t user_access;
    guid_t guid;
    guid_t uuid;
    struct kauth_filesec file_sec;
    int fileSecLength;
    uint64_t common_file_id;
    uint64_t parent_id;
    struct timespec add_time;
    uint64_t file_link_count;
    off_t file_total_size;
    off_t file_alloc_size;
    u_int32_t file_io_size;
    dev_t dev_type;
    off_t file_data_length;
    off_t file_data_logic_size;
    off_t file_rsrc_fork;
    off_t file_rsrc_alloc_size;
    uint32_t dir_link_count;
    uint32_t dir_entry_count;
    uint32_t dir_mount_status;
    
};

/* Setting this value will change how many getdirentriesattr() will do only if
 * getattrlistbulk() is NOT being used. Bulk fills all the space it is given, so
 * in most cases it will get more than the number specified here, unless, of
 * course, there are less than this many entries in the directory. */
enum {
    kEntriesPerCall = 150
};

char objType[10][10] = { "none", "VREG", "VDIR", "VBLK", "VCHR", "VLNK", "VSOCK", "VFIFO" };
char cmnAccess[10][10] = { "---", "--X", "-W-", "-WX", "R--", "R-X", "RW-", "RWX" };
char objTag[30][10] = { "VT_NON", "VT_UFS", "VT_NFS", "VT_MFS", "VT_MSDOSFS", "VT_LFS", "VT_LOFS", "VT_FDESC",
    "VT_PORTAL", "VT_NULL", "VT_UMAP", "VT_KERNFS", "VT_PROCFS", "VT_AFS", "VT_ISOFS",
    "VT_MOCKFS", "VT_HFS", "VT_ZFS", "VT_DEVFS", "VT_WEBDAV", "VT_UDF", "VT_AFP",
    "VT_CDDA", "VT_CIFS", "VT_OTHER"};

void PrintDirEntriesBulk(attribute_set_t requested_attributes, int count, char *attrBuf, long *item_cnt)
{
    u_int32_t *attr_length;
    attribute_set_t *attrs_returned;
    unsigned long index = 0;
    char *tptr;
    FileInfo *finfo = NULL;
    FolderInfo *folderInfo = NULL;
    ExtendedFileInfo *exFinfo = NULL;
    ExtendedFolderInfo *exFolderInfo = NULL;
    char mode_str[20];
    fsobj_type_t obj_type = VREG;
    char *curr, *start;
    attrreference_t *attref_ptr;
    dev_t *dev_ptr;
    fsid_t *fsid_ptr;
    fsobj_type_t *fsobj_type_ptr;
    fsobj_tag_t *fsobj_tag_ptr;
    fsobj_id_t *fsobj_id_ptr;
    text_encoding_t *encoding_ptr;
    struct timespec *time_ptr;
    uid_t *uid_ptr;
    gid_t *gid_ptr;
    u_int32_t *uint32_ptr;
    u_int64_t *uint64_ptr;
    off_t *off_t_ptr;
    guid_t *guid_ptr;
    //struct kauth_filesec *file_sec_ptr;
    
    curr = (char *) attrBuf;
    
    for (index = 0; index < count; index++) {
        *item_cnt += 1;
        
        /* Save length of this attribute entry */
        start = curr;
        attr_length = (u_int32_t *) curr;
        curr += sizeof(u_int32_t);
        
        /* Save returned attributes for this attribute entry */
        attrs_returned = (attribute_set_t *) curr;
        curr += sizeof(attribute_set_t);
        
#if 0
        if (gSetInvalOpt) {
            /*
             * if FSOPT_PACK_INVAL_ATTRS was used, then all the attributes
             * we requested were returned, but some may be filled with
             * default values. Thus set attrs_returned to be the same as
             * what we requested.
             *
             * ATTR_CMN_RETURNED_ATTRS just tells us which attributes were
             * actually filled in with real values in this case. Not used for
             * now.
             */
            attrs_returned = &requested_attributes;
        }
#endif
        if (attrs_returned->commonattr & ATTR_CMN_NAME) {
            attref_ptr = (attrreference_t *) curr;
            printf("Name: %s\n", ((char *) attref_ptr) + attref_ptr->attr_dataoffset);
            curr += sizeof(attrreference_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_NAME) {
                fprintf(stderr, "Name not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_DEVID) {
            dev_ptr = (dev_t *) curr;
            printf("Dev ID: %d (0x%x)\n", *dev_ptr, *dev_ptr);
            curr += sizeof(dev_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_DEVID) {
                fprintf(stderr, "Dev ID not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_FSID) {
            fsid_ptr = (fsid_t *) curr;
            printf("FS ID: %d:%d (0x%x:0x%x)\n",
                   fsid_ptr->val[0], fsid_ptr->val[1],
                   fsid_ptr->val[0], fsid_ptr->val[1]);
            curr += sizeof(fsid_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_FSID) {
                fprintf(stderr, "FS ID not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_OBJTYPE) {
            fsobj_type_ptr = (fsobj_type_t *) curr;
            obj_type = *fsobj_type_ptr;
            printf("Object Type: %d (%s) \n", *fsobj_type_ptr, objType[*fsobj_type_ptr]);
            curr += sizeof(fsobj_type_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_OBJTYPE) {
                fprintf(stderr, "Object Type not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_OBJTAG) {
            fsobj_tag_ptr = (fsobj_tag_t *) curr;
            printf("Object Tag: %d (%s)\n", *fsobj_tag_ptr, objTag[*fsobj_tag_ptr]);
            curr += sizeof(fsobj_tag_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_OBJTAG) {
                fprintf(stderr, "Object Tag not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_OBJID) {
            fsobj_id_ptr = (fsobj_id_t *) curr;
            printf("Object ID: %d:%d (0x%x:0x%x)\n",
                   fsobj_id_ptr->fid_objno, fsobj_id_ptr->fid_generation,
                   fsobj_id_ptr->fid_objno, fsobj_id_ptr->fid_generation);
            curr += sizeof(fsobj_id_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_OBJID) {
                fprintf(stderr, "Object ID not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_OBJPERMANENTID) {
            fsobj_id_ptr = (fsobj_id_t *) curr;
            printf("Object Permanent ID: %d:%d (0x%x:0x%x)\n",
                   fsobj_id_ptr->fid_objno, fsobj_id_ptr->fid_generation,
                   fsobj_id_ptr->fid_objno, fsobj_id_ptr->fid_generation);
            curr += sizeof(fsobj_id_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_OBJPERMANENTID) {
                fprintf(stderr, "Permanent ID not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_PAROBJID) {
            fsobj_id_ptr = (fsobj_id_t *) curr;
            printf("Parent Object ID: %d:%d (0x%x:0x%x)\n",
                   fsobj_id_ptr->fid_objno, fsobj_id_ptr->fid_generation,
                   fsobj_id_ptr->fid_objno, fsobj_id_ptr->fid_generation);
            curr += sizeof(fsobj_id_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_PAROBJID) {
                fprintf(stderr, "Parent Object ID not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_SCRIPT) {
            encoding_ptr = (text_encoding_t *) curr;
            printf("Script: %d (0x%x)\n", *encoding_ptr, *encoding_ptr);
            curr += sizeof(text_encoding_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_SCRIPT) {
                fprintf(stderr, "Script not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_CRTIME) {
            time_ptr = (struct timespec *) curr;
            printf("Create Time: %s", ctime(&time_ptr->tv_sec));
            curr += sizeof(struct timespec);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_CRTIME) {
                fprintf(stderr, "Create Time not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_MODTIME) {
            time_ptr = (struct timespec *) curr;
            printf("Mod Time: %s", ctime(&time_ptr->tv_sec));
            curr += sizeof(struct timespec);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_MODTIME) {
                fprintf(stderr, "Mod Time not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_CHGTIME) {
            time_ptr = (struct timespec *) curr;
            printf("Change Time: %s", ctime(&time_ptr->tv_sec));
            curr += sizeof(struct timespec);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_CHGTIME) {
                fprintf(stderr, "Change Time not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_ACCTIME) {
            time_ptr = (struct timespec *) curr;
            printf("Access Time: %s", ctime(&time_ptr->tv_sec));
            curr += sizeof(struct timespec);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_ACCTIME) {
                fprintf(stderr, "Access Time not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_BKUPTIME) {
            time_ptr = (struct timespec *) curr;
            printf("Backup Time: %s", ctime(&time_ptr->tv_sec));
            curr += sizeof(struct timespec);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_BKUPTIME) {
                fprintf(stderr, "Backup Time not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_FNDRINFO) {
            /* print this out later */
            finfo = (FileInfo *) curr;
            folderInfo = (FolderInfo *) curr;
            curr += 16;
            
            exFinfo = (ExtendedFileInfo *) curr;
            exFolderInfo = (ExtendedFolderInfo *) curr;
            curr += 16;
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_FNDRINFO) {
                fprintf(stderr, "Finder Info not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_OWNERID) {
            uid_ptr = (uid_t *) curr;
            printf("Common Owner ID: %d (0x%x) \n", *uid_ptr, *uid_ptr);
            curr += sizeof(uid_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_OWNERID) {
                fprintf(stderr, "Owner ID not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_GRPID) {
            gid_ptr = (gid_t *) curr;
            printf("Common Group ID: %ud (0x%x) \n", *gid_ptr, *gid_ptr);
            curr += sizeof(gid_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_GRPID) {
                fprintf(stderr, "Group ID not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_ACCESSMASK) {
            uint32_ptr = (u_int32_t *) curr;
            strmode(*uint32_ptr, mode_str);
            printf("Common Access Mask: 0x%x (%s) \n", *uint32_ptr, mode_str);
            curr += sizeof(u_int32_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_ACCESSMASK) {
                fprintf(stderr, "Access Mask not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_FLAGS) {
            uint32_ptr = (u_int32_t *) curr;
            printf("Common Flags: 0x%x \n", *uint32_ptr);
            curr += sizeof(u_int32_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_FLAGS) {
                fprintf(stderr, "Flags not returned\n");
            }
        }
        
#if 0
        if (attrs_returned->commonattr & ATTR_CMN_GEN_COUNT) {
            uint32_ptr = (u_int32_t *) curr;
            printf("Common Generation Count: 0x%x \n", *uint32_ptr);
            curr += sizeof(u_int32_t);
        }
        else {
            fprintf(stderr, "Common Generation Count not returned\n");
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_DOCUMENT_ID) {
            uint32_ptr = (u_int32_t *) curr;
            printf("Common Document ID: 0x%x \n", *uint32_ptr);
            curr += sizeof(u_int32_t);
        }
        else {
            fprintf(stderr, "Common Document ID not returned\n");
        }
#endif
        
        if (attrs_returned->commonattr & ATTR_CMN_USERACCESS) {
            uint32_ptr = (u_int32_t *) curr;
            printf("Common UserAccess: 0x%x (%s)\n", *uint32_ptr, cmnAccess[*uint32_ptr]);
            curr += sizeof(u_int32_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_USERACCESS) {
                fprintf(stderr, "User Access not returned\n");
            }
        }
        
#if 0
        if (attrs_returned->commonattr & ATTR_CMN_EXTENDED_SECURITY) {
            attref_ptr = (attrreference_t *) curr;
            printf("length %d, offset %d\n", attref_ptr->attr_length, attref_ptr->attr_dataoffset);
            
            tptr = curr;
            tptr += attref_ptr->attr_dataoffset;
            
            
            file_sec_ptr = (struct kauth_filesec *) tptr;
            
            printf("magic 0x%x acl_entrycount %d acl_flags 0x%x\n",
                   file_sec_ptr->fsec_magic,
                   file_sec_ptr->fsec_acl.acl_entrycount,
                   file_sec_ptr->fsec_acl.acl_flags);
            smb_print_acl(&file_sec_ptr->fsec_acl);
            curr += sizeof(attrreference_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_EXTENDED_SECURITY) {
                fprintf(stderr, "Extended Security not returned\n");
            }
        }
#endif
        if (attrs_returned->commonattr & ATTR_CMN_UUID) {
            guid_ptr = (guid_t *) curr;
            printf("UUID: 0x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x\n",
                   guid_ptr->g_guid[0], guid_ptr->g_guid[1], guid_ptr->g_guid[2], guid_ptr->g_guid[3],
                   guid_ptr->g_guid[4], guid_ptr->g_guid[5], guid_ptr->g_guid[6], guid_ptr->g_guid[7],
                   guid_ptr->g_guid[8], guid_ptr->g_guid[9], guid_ptr->g_guid[10], guid_ptr->g_guid[11],
                   guid_ptr->g_guid[12], guid_ptr->g_guid[13], guid_ptr->g_guid[14], guid_ptr->g_guid[15]
                   );
            curr += sizeof(guid_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_UUID) {
                fprintf(stderr, "UUID not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_GRPUUID) {
            guid_ptr = (guid_t *) curr;
            printf("Group UUID: 0x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x\n",
                   guid_ptr->g_guid[0], guid_ptr->g_guid[1], guid_ptr->g_guid[2], guid_ptr->g_guid[3],
                   guid_ptr->g_guid[4], guid_ptr->g_guid[5], guid_ptr->g_guid[6], guid_ptr->g_guid[7],
                   guid_ptr->g_guid[8], guid_ptr->g_guid[9], guid_ptr->g_guid[10], guid_ptr->g_guid[11],
                   guid_ptr->g_guid[12], guid_ptr->g_guid[13], guid_ptr->g_guid[14], guid_ptr->g_guid[15]
                   );
            curr += sizeof(guid_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_GRPUUID) {
                fprintf(stderr, "Group UUID not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_FILEID) {
            uint64_ptr = (u_int64_t *) curr;
            printf("Common File ID: %lld (0x%llx) \n", *uint64_ptr, *uint64_ptr);
            curr += sizeof(u_int64_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_FILEID) {
                fprintf(stderr, "File ID not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_PARENTID) {
            uint64_ptr = (u_int64_t *) curr;
            printf("Common Parent ID: %lld (0x%llx) \n", *uint64_ptr, *uint64_ptr);
            curr += sizeof(u_int64_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_PARENTID) {
                fprintf(stderr, "Parent ID not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_FULLPATH) {
            attref_ptr = (attrreference_t *) curr;
            printf("Common Full Path: %s\n", ((char *) attref_ptr) + attref_ptr->attr_dataoffset);
            curr += sizeof(attrreference_t);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_FULLPATH) {
                fprintf(stderr, "Common Full Path not returned\n");
            }
        }
        
        if (attrs_returned->commonattr & ATTR_CMN_ADDEDTIME) {
            time_ptr = (struct timespec *) curr;
            printf("Added Time: %s", ctime(&time_ptr->tv_sec));
            curr += sizeof(struct timespec);
        }
        else {
            if (requested_attributes.commonattr & ATTR_CMN_ADDEDTIME) {
                fprintf(stderr, "Added Time not returned\n");
            }
        }
        
#if 0
        if (attrs_returned->commonattr & ATTR_CMN_DATA_PROTECT_FLAGS) {
            uint32_ptr = (u_int32_t *) curr;
            printf("Common Data Protect Flags: 0x%x (%s)\n", *uint32_ptr, cmnAccess[*uint32_ptr]);
            curr += sizeof(u_int32_t);
        }
        else {
            fprintf(stderr, "User Data Protect Flags not returned\n");
        }
#endif
        
        switch (obj_type) {
            case VLNK:
            case VREG:
                if (attrs_returned->commonattr & ATTR_CMN_FNDRINFO) {
                    if (finfo == NULL) {
                        fprintf(stderr, "Common Finder Info: finfo is NULL \n");
                    }
                    else {
                        tptr = (char*) &finfo->fileType;
                        printf("Common Finder Info: fileType <%c%c%c%c> 0x%x:0x%x:0x%x:0x%x\n",
                               tptr[0], tptr[1], tptr[2], tptr[3],
                               tptr[0], tptr[1], tptr[2], tptr[3]
                               );

                        tptr = (char*) &finfo->fileCreator;
                        printf("Common Finder Info: fileCreator <%c%c%c%c> 0x%x:0x%x:0x%x:0x%x\n",
                               tptr[0], tptr[1], tptr[2], tptr[3],
                               tptr[0], tptr[1], tptr[2], tptr[3]
                               );

                        printf("Common Finder Info: finderFlags %d\n", finfo->finderFlags);
                        printf("Common Finder Info: location v %d h %d\n",
                               finfo->location.v,
                               finfo->location.h);
                        printf("Common Finder Info: reservedField %d\n", finfo->reservedField);
                        printf("Common Finder Info: reserved %d %d %d %d\n",
                               exFinfo->reserved1[0],
                               exFinfo->reserved1[1],
                               exFinfo->reserved1[2],
                               exFinfo->reserved1[3]);
                        printf("Common Finder Info: extendedFinderFlags %d\n", exFinfo->extendedFinderFlags);
                        printf("Common Finder Info: reserved2 %d\n", exFinfo->reserved2);
                        printf("Common Finder Info: putAwayFolderID %d\n", exFinfo->putAwayFolderID);
                    }
                }
                
                if (attrs_returned->fileattr & ATTR_FILE_LINKCOUNT) {
                    uint32_ptr = (u_int32_t *) curr;
                    printf("File Link Count: %d \n", *uint32_ptr);
                    curr += sizeof(u_int32_t);
                }
                else {
                    if (requested_attributes.fileattr & ATTR_FILE_LINKCOUNT) {
                        fprintf(stderr, "File Link Count not returned\n");
                    }
                }
                
                if (attrs_returned->fileattr & ATTR_FILE_TOTALSIZE) {
                    off_t_ptr = (off_t *) curr;
                    printf("File Total Size: %lld (0x%llx)\n", *off_t_ptr, *off_t_ptr);
                    curr += sizeof(off_t);
                }
                else {
                    if (requested_attributes.fileattr & ATTR_FILE_TOTALSIZE) {
                        fprintf(stderr, "File Total Size not returned\n");
                    }
                }
                
                if (attrs_returned->fileattr & ATTR_FILE_ALLOCSIZE) {
                    off_t_ptr = (off_t *) curr;
                    printf("File Alloc Size: %lld (0x%llx)\n", *off_t_ptr, *off_t_ptr);
                    curr += sizeof(off_t);
                }
                else {
                    if (requested_attributes.fileattr & ATTR_FILE_ALLOCSIZE) {
                        fprintf(stderr, "File Alloc Size not returned\n");
                    }
                }
                
                if (attrs_returned->fileattr & ATTR_FILE_IOBLOCKSIZE) {
                    uint32_ptr = (u_int32_t *) curr;
                    printf("File IO Size: %d (0x%x)\n", *uint32_ptr, *uint32_ptr);
                    curr += sizeof(u_int32_t);
                }
                else {
                    if (requested_attributes.fileattr & ATTR_FILE_IOBLOCKSIZE) {
                        fprintf(stderr, "File IO Block Size not returned\n");
                    }
                }
                
                if (attrs_returned->fileattr & ATTR_FILE_DEVTYPE) {
                    dev_ptr = (dev_t *) curr;
                    printf("File Dev Type: %d \n", *dev_ptr);
                    curr += sizeof(dev_t);
                }
                else {
                    if (requested_attributes.fileattr & ATTR_FILE_DEVTYPE) {
                        fprintf(stderr, "File Dev Type not returned\n");
                    }
                }
                
                if (attrs_returned->fileattr & ATTR_FILE_DATALENGTH) {
                    off_t_ptr = (off_t *) curr;
                    printf("File Data Fork Logical Length: %lld (0x%llx)\n", *off_t_ptr, *off_t_ptr);
                    curr += sizeof(off_t);
                }
                else {
                    if (requested_attributes.fileattr & ATTR_FILE_DATALENGTH) {
                        fprintf(stderr, "File Data Length not returned\n");
                    }
                }
                
                if (attrs_returned->fileattr & ATTR_FILE_DATAALLOCSIZE) {
                    off_t_ptr = (off_t *) curr;
                    printf("File Data Fork Physical Length: %lld (0x%llx)\n", *off_t_ptr, *off_t_ptr);
                    curr += sizeof(off_t);
                }
                else {
                    if (requested_attributes.fileattr & ATTR_FILE_DATAALLOCSIZE) {
                        fprintf(stderr, "File Data Alloc Size not returned\n");
                    }
                }
                
                if (attrs_returned->fileattr & ATTR_FILE_RSRCLENGTH) {
                    off_t_ptr = (off_t *) curr;
                    printf("File Rsrc Fork Logical Length: %lld (0x%llx)\n", *off_t_ptr, *off_t_ptr);
                    curr += sizeof(off_t);
                }
                else {
                    if (requested_attributes.fileattr & ATTR_FILE_RSRCLENGTH) {
                        fprintf(stderr, "File Resource Length not returned\n");
                    }
                }
                
                if (attrs_returned->fileattr & ATTR_FILE_RSRCALLOCSIZE) {
                    off_t_ptr = (off_t *) curr;
                    printf("File Rsrc Fork Physical Length: %lld (0x%llx)\n", *off_t_ptr, *off_t_ptr);
                    //curr += sizeof(off_t);
                }
                else {
                    if (requested_attributes.fileattr & ATTR_FILE_RSRCALLOCSIZE) {
                        fprintf(stderr, "File Resource Alloc Size not returned\n");
                    }
                }
                
                printf("\n");
                break;
            case VDIR:
                if (attrs_returned->commonattr & ATTR_CMN_FNDRINFO) {
                    if (folderInfo == NULL) {
                        fprintf(stderr, "Common Finder Info: folderInfo is NULL \n");
                    }
                    else {
                        printf("Common Finder Info: windowBounds top %d left %d bottom %d right %d\n",
                               folderInfo->windowBounds.top,
                               folderInfo->windowBounds.left,
                               folderInfo->windowBounds.bottom,
                               folderInfo->windowBounds.right);
                        printf("Common Finder Info: finderFlags %d\n", folderInfo->finderFlags);
                        printf("Common Finder Info: location v %d h %d\n",
                               folderInfo->location.v,
                               folderInfo->location.h);
                        printf("Common Finder Info: reservedField %d\n", folderInfo->reservedField);
                        printf("Common Finder Info: scrollPosition v %d h %d\n",
                               exFolderInfo->scrollPosition.v,
                               exFolderInfo->scrollPosition.h);
                        printf("Common Finder Info: reserved1 %d\n", exFolderInfo->reserved1);
                        printf("Common Finder Info: extendedFinderFlags %d\n", exFolderInfo->extendedFinderFlags);
                        printf("Common Finder Info: reserved2 %d\n", exFolderInfo->reserved2);
                        printf("Common Finder Info: putAwayFolderID %d\n", exFolderInfo->putAwayFolderID);
                    }
                }
                
                if (attrs_returned->dirattr & ATTR_DIR_LINKCOUNT) {
                    uint32_ptr = (u_int32_t *) curr;
                    printf("Dir Link Count: %d (0x%x)\n", *uint32_ptr, *uint32_ptr);
                    curr += sizeof(u_int32_t);
                }
                else {
                    if (requested_attributes.dirattr & ATTR_DIR_LINKCOUNT) {
                        fprintf(stderr, "Dir Link Count not returned\n");
                    }
                }
                
                if (attrs_returned->dirattr & ATTR_DIR_ENTRYCOUNT) {
                    uint32_ptr = (u_int32_t *) curr;
                    printf("Dir Entry Count: %d (0x%x)\n", *uint32_ptr, *uint32_ptr);
                    curr += sizeof(u_int32_t);
                }
                else {
                    if (requested_attributes.dirattr & ATTR_DIR_ENTRYCOUNT) {
                        fprintf(stderr, "Dir Entry Count not returned\n");
                    }
                }
                
                if (attrs_returned->dirattr & ATTR_DIR_MOUNTSTATUS) {
                    uint32_ptr = (u_int32_t *) curr;
                    printf("Dir Mount Status:  %d (0x%x)", *uint32_ptr, *uint32_ptr);
                    if (*uint32_ptr) {
                        if (*uint32_ptr & DIR_MNTSTATUS_MNTPOINT) {
                            printf(", mount point");
                        }
                        if (*uint32_ptr & DIR_MNTSTATUS_TRIGGER) {
                            printf(", trigger point");
                        }
                    }
                    printf("\n");
                    //curr += sizeof(u_int32_t);
                }
                else {
                    if (requested_attributes.dirattr & ATTR_DIR_MOUNTSTATUS) {
                        fprintf(stderr, "Dir Mount Status not returned\n");
                    }
                }
                
                printf("\n");
                break;
            default:
                break;
        }
        
        // Advance to the next entry.
        curr = start + *attr_length;
    } /* End of for loop */
}

-(void)testNoXattrSupportWithNoXattrs
{
    __block int error = 0;
    char base_file_path[PATH_MAX];
    char file_path[PATH_MAX];
    int fd = -1;
    __block int i;
    __block int test_file_cnt = 1000;
    __block int mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH; /* -rw-rw-rw- */
    char mp1[PATH_MAX];
    char *mount_path = mp1;

    /*
     * We will need just one mount to start with
     */
    do_create_mount_path(mp1, sizeof(mp1), "testNoXattrSupportWithNoXattrsMp1");

    error = mount_two_sessions(mp1, NULL, 0);
    if (error) {
        XCTFail("mount_two_sessions failed %d \n", error);
        goto err_out;
    }
    
    /* Create the test dirs */
    error = do_create_test_dirs(mp1);
    if (error) {
        XCTFail("do_create_test_dirs on <%s> failed %d:%s \n", mp1,
               error, strerror(error));
        goto err_out;
    }
    
    /* Set up file path */
    strlcpy(base_file_path, mp1, sizeof(base_file_path));
    strlcat(base_file_path, "/", sizeof(base_file_path));
    strlcat(base_file_path, cur_test_dir, sizeof(base_file_path));
    

    /* Create a bunch of test files to enumerate without xattrs */
    printf("Creating %d test files \n", test_file_cnt);
    for (i = 0; i < test_file_cnt; i++) {
        sprintf(file_path, "%s/%s_%d",
                base_file_path, default_test_filename, i);
        
        /* Create the test files on mp1 */
        fd = open(file_path, O_RDONLY | O_CREAT, mode);
        if (fd == -1) {
            XCTFail("Create on <%s> failed %d:%s \n", file_path,
                    errno, strerror(errno));
            error = errno;
            goto err_out;
        }
        else {
            error = close(fd);
            if (error) {
                XCTFail("close on <%s> failed %d:%s \n", file_path,
                        errno, strerror(errno));
                error = errno;
                goto err_out;
            }
        }
    }
    
err_out:
    if (error) {
        if (unmount(mp1, MNT_FORCE) == -1) {
            XCTFail("unmount failed for first url %d\n", errno);
        }
        
        rmdir(mp1);

        return;
    }

    /* Turn down verbosity before the performance test */
    gVerbose = 0;
    
    printf("Starting performance part of test \n");

    [self measureBlock:^{
        int numReturnedBulk = 0;
        int total_returned = 0;
        int dirBulkReplySize = 0;
        char *dirBulkReplyPtr = NULL;
        attribute_set_t req_attrs = {0};
        char base_file_path[PATH_MAX];
        char file_path[PATH_MAX];
        ssize_t xattr_size = 0;
        int xattr_options = XATTR_NOFOLLOW;
        char dir_path[PATH_MAX];
        int fd = -1;
        int dir_fd = -1;
        long item_cnt = 0;

        strlcpy(base_file_path, mount_path, sizeof(base_file_path));
        strlcat(base_file_path, "/", sizeof(base_file_path));
        strlcat(base_file_path, cur_test_dir, sizeof(base_file_path));

        /* Save path to test dir */
        strlcpy(dir_path, base_file_path, sizeof(dir_path));

        /* Create a file, then delete it to invalidate any dir enum caching */
        sprintf(file_path, "%s/%s",
                base_file_path, default_test_filename);

        /* Create the test file on mp1 */
        fd = open(file_path, O_RDONLY | O_CREAT, mode);
        if (fd == -1) {
            XCTFail("Create on <%s> failed %d:%s \n", file_path,
                    errno, strerror(errno));
            error = errno;
            goto done;
        }
        else {
            error = close(fd);
            if (error) {
                XCTFail("close on <%s> failed %d:%s \n", file_path,
                        errno, strerror(errno));
                error = errno;
                goto done;
            }
            //fd = -1;
            
            error = unlink(file_path);
            if (error) {
                XCTFail("unlink on <%s> failed %d:%s \n", file_path,
                        errno, strerror(errno));
                error = errno;
                goto done;
            }
        }

        /*
         * Open the test dir on mp1
         */
        dir_fd = open(dir_path, O_RDONLY);
        if (dir_fd == -1) {
            XCTFail("open on <%s> failed %d:%s \n", dir_path,
                    errno, strerror(errno));
            error = errno;
            goto done;
        }

        dirBulkReplySize = kEntriesPerCall * (sizeof(struct replyData)) + 1024;
        dirBulkReplyPtr = malloc(dirBulkReplySize);
        total_returned = 0;
        
        do {
            numReturnedBulk = getAttrListBulk(dir_fd, dirBulkReplySize,
                                              dirBulkReplyPtr, &req_attrs);
            if (numReturnedBulk < 0) {
                XCTFail("getAttrListBulk failed %d:%s \n",
                        errno, strerror(errno));
                error = errno;
                goto done;
            }
            
            total_returned += numReturnedBulk;
            if (gVerbose) {
                printf("Got %d entries. Total %d \n",
                       numReturnedBulk, total_returned);
                PrintDirEntriesBulk(req_attrs, numReturnedBulk,
                                    dirBulkReplyPtr, &item_cnt);
            }
        } while (numReturnedBulk != 0);
        
        if (total_returned < test_file_cnt) {
            XCTFail("Did not enumerate all the files %d != %d \n",
                    total_returned,test_file_cnt);
            error = EINVAL;
            goto done;
        }

        /* Do listxattr on all the files on mp1 */
        for (i = 0; i < test_file_cnt; i++) {
            sprintf(file_path, "%s/%s_%d",
                    base_file_path, default_test_filename, i);

            /* Do listxattr */
            xattr_size = listxattr(file_path, NULL, 0, xattr_options);
            if (xattr_size != 0) {
                XCTFail("listxattr on <%s> with no xattrs failed %zd %d:%s \n",
                        file_path, xattr_size, errno, strerror(errno));
                error = errno;
                goto done;
            }
        }
        
    done:
        if (dirBulkReplyPtr != NULL) {
            free(dirBulkReplyPtr);
            dirBulkReplyPtr = NULL;
        }
        
        /* Close test dir */
        if (dir_fd != -1) {
            error = close(dir_fd);
            if (error) {
                XCTFail("close on dir_fd failed %d:%s \n", errno, strerror(errno));
                error = errno;
            }
        }

        return;
    }];
    
    /* Delete all the files on mp1 */
    for (i = 0; i < test_file_cnt; i++) {
        sprintf(file_path, "%s/%s_%d",
                base_file_path, default_test_filename, i);
        
        /* Do delete */
        error = unlink(file_path);
        if (error) {
            fprintf(stderr, "cleanup unlink on <%s> failed %d:%s \n",
                    file_path, errno, strerror(errno));
        }
    }
    
    /*
     * If no errors, attempt to delete test dirs. This could fail if a
     * previous test failed and thats fine.
     */
    do_delete_test_dirs(mp1);
    
    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("unmount failed for first url %d\n", errno);
    }
    
    rmdir(mp1);
}

-(void)testNoXattrSupportWithXattrs
{
    __block int error = 0;
    char base_file_path[PATH_MAX];
    char file_path[PATH_MAX];
    int fd = -1;
    __block int i;
    __block int test_file_cnt = 1000;
    __block int mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH; /* -rw-rw-rw- */
    char mp1[PATH_MAX];
    char *mount_path = mp1;
#define kXattrData "test_value"
    
    /*
     * We will need just one mount to start with
     */
    do_create_mount_path(mp1, sizeof(mp1), "testNoXattrSupportWithXattrsMp1");

    error = mount_two_sessions(mp1, NULL, 0);
    if (error) {
        XCTFail("mount_two_sessions failed %d \n", error);
        goto err_out;
    }
    
    /* Create the test dirs */
    error = do_create_test_dirs(mp1);
    if (error) {
        XCTFail("do_create_test_dirs on <%s> failed %d:%s \n", mp1,
               error, strerror(error));
        goto err_out;
    }
    
    /* Set up file path */
    strlcpy(base_file_path, mp1, sizeof(base_file_path));
    strlcat(base_file_path, "/", sizeof(base_file_path));
    strlcat(base_file_path, root_test_dir, sizeof(base_file_path));
    
    /* Add an xattr to root test dir */
    error = setxattr(base_file_path, "test_xattr", kXattrData,
                     sizeof(kXattrData), 0, XATTR_NOFOLLOW);
    if (error) {
        XCTFail("setxattr on <%s> failed %d:%s \n", base_file_path,
                errno, strerror(errno));
        error = errno;
        goto err_out;
    }

    strlcpy(base_file_path, mp1, sizeof(base_file_path));
    strlcat(base_file_path, "/", sizeof(base_file_path));
    strlcat(base_file_path, cur_test_dir, sizeof(base_file_path));

    /* Add an xattr to test dir */
    error = setxattr(base_file_path, "test_xattr", kXattrData,
                     sizeof(kXattrData), 0, XATTR_NOFOLLOW);
    if (error) {
        XCTFail("setxattr on <%s> failed %d:%s \n", base_file_path,
                errno, strerror(errno));
        error = errno;
        goto err_out;
    }

    /* Create a bunch of test files to enumerate with xattrs */
    printf("Creating %d test files \n", test_file_cnt);
    for (i = 0; i < test_file_cnt; i++) {
        sprintf(file_path, "%s/%s_%d",
                base_file_path, default_test_filename, i);
        
        /* Create the test files on mp1 */
        fd = open(file_path, O_RDONLY | O_CREAT, mode);
        if (fd == -1) {
            XCTFail("Create on <%s> failed %d:%s \n", file_path,
                    errno, strerror(errno));
            error = errno;
            goto err_out;
        }
        else {
            error = close(fd);
            if (error) {
                XCTFail("close on <%s> failed %d:%s \n", file_path,
                        errno, strerror(errno));
                error = errno;
                goto err_out;
            }
            
            /* Add an xattr */
            error = setxattr(file_path, "test_xattr", kXattrData,
                             sizeof(kXattrData), 0, XATTR_NOFOLLOW);
            if (error) {
                XCTFail("setxattr on <%s> failed %d:%s \n", file_path,
                        errno, strerror(errno));
                error = errno;
                goto err_out;
            }
        }
    }
    
err_out:
    if (error) {
        if (unmount(mp1, MNT_FORCE) == -1) {
            XCTFail("unmount failed for first url %d\n", errno);
        }
        
        rmdir(mp1);
        
        return;
    }
    
    /* Turn down verbosity before the performance test */
    gVerbose = 0;
    
    printf("Starting performance part of test \n");

    [self measureBlock:^{
        int numReturnedBulk = 0;
        int total_returned = 0;
        int dirBulkReplySize = 0;
        char *dirBulkReplyPtr = NULL;
        attribute_set_t req_attrs = {0};
        char base_file_path[PATH_MAX];
        char file_path[PATH_MAX];
        ssize_t xattr_size = 0;
        int xattr_options = XATTR_NOFOLLOW;
        char dir_path[PATH_MAX];
        int fd = -1;
        int dir_fd = -1;
        long item_cnt = 0;
        
        strlcpy(base_file_path, mount_path, sizeof(base_file_path));
        strlcat(base_file_path, "/", sizeof(base_file_path));
        strlcat(base_file_path, cur_test_dir, sizeof(base_file_path));
        
        /* Save path to test dir */
        strlcpy(dir_path, base_file_path, sizeof(dir_path));
        
        /* Create a file, then delete it to invalidate any dir enum caching */
        sprintf(file_path, "%s/%s",
                base_file_path, default_test_filename);
        
        /* Create the test file on mp1 */
        fd = open(file_path, O_RDONLY | O_CREAT, mode);
        if (fd == -1) {
            XCTFail("Create on <%s> failed %d:%s \n", file_path,
                    errno, strerror(errno));
            error = errno;
            goto done;
        }
        else {
            error = close(fd);
            if (error) {
                XCTFail("close on <%s> failed %d:%s \n", file_path,
                        errno, strerror(errno));
                error = errno;
                goto done;
            }
            
            error = unlink(file_path);
            if (error) {
                XCTFail("unlink on <%s> failed %d:%s \n", file_path,
                        errno, strerror(errno));
                error = errno;
                goto done;
            }
        }
        
        /*
         * Open the test dir on mp1
         */
        dir_fd = open(dir_path, O_RDONLY);
        if (dir_fd == -1) {
            XCTFail("open on <%s> failed %d:%s \n", dir_path,
                    errno, strerror(errno));
            error = errno;
            goto done;
        }
        
        dirBulkReplySize = kEntriesPerCall * (sizeof(struct replyData)) + 1024;
        dirBulkReplyPtr = malloc(dirBulkReplySize);
        total_returned = 0;

        do {
            numReturnedBulk = getAttrListBulk(dir_fd, dirBulkReplySize,
                                              dirBulkReplyPtr, &req_attrs);
            if (numReturnedBulk < 0) {
                XCTFail("getAttrListBulk failed %d:%s \n",
                        errno, strerror(errno));
                error = errno;
                goto done;
            }
            
            total_returned += numReturnedBulk;
            if (gVerbose) {
                printf("Got %d entries. Total %d \n",
                       numReturnedBulk, total_returned);
                PrintDirEntriesBulk(req_attrs, numReturnedBulk,
                                    dirBulkReplyPtr, &item_cnt);
            }
        } while (numReturnedBulk != 0);
        
        if (total_returned < test_file_cnt) {
            XCTFail("Did not enumerate all the files %d != %d \n",
                    total_returned,test_file_cnt);
            error = EINVAL;
            goto done;
        }

        /* Do listxattr on all the files on mp1 */
        for (i = 0; i < test_file_cnt; i++) {
            sprintf(file_path, "%s/%s_%d",
                    base_file_path, default_test_filename, i);
            
            /* Do listxattr */
            xattr_size = listxattr(file_path, NULL, 0, xattr_options);
            if (xattr_size != sizeof(kXattrData)) {
                XCTFail("listxattr on <%s> with no xattrs failed %zd != %lu\n",
                        file_path, xattr_size, sizeof(kXattrData));
                error = errno;
                goto done;
            }
        }
        
    done:
        if (dirBulkReplyPtr != NULL) {
            free(dirBulkReplyPtr);
            dirBulkReplyPtr = NULL;
        }

        /* Close test dir */
        if (dir_fd != -1) {
            error = close(dir_fd);
            if (error) {
                XCTFail("close on dir_fd failed %d:%s \n", errno, strerror(errno));
                error = errno;
            }
        }

        return;
    }];
    
    /* Delete all the files on mp1 */
    for (i = 0; i < test_file_cnt; i++) {
        sprintf(file_path, "%s/%s_%d",
                base_file_path, default_test_filename, i);
        
        /* Do delete */
        error = unlink(file_path);
        if (error) {
            fprintf(stderr, "cleanup unlink on <%s> failed %d:%s \n",
                    file_path, errno, strerror(errno));
        }
    }

    /*
     * If no errors, attempt to delete test dirs. This could fail if a
     * previous test failed and thats fine.
     */
    do_delete_test_dirs(mp1);
    
    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("unmount failed for first url %d\n", errno);
    }
    
    rmdir(mp1);
}

/* Unit test for 59146570 */
-(void)testReadDirOfSymLink
{
    int error = 0;
    char dir_path[PATH_MAX];
    char test_dir_path[PATH_MAX];
    char test_file_path[PATH_MAX];
    char symlink_path[PATH_MAX];
    char stat_path[PATH_MAX];
    int fd = -1;
    int oflag = O_CREAT | O_RDWR;
    struct dirent *dp;
    DIR * dirp;
    struct stat sb;
    int item_count = 0;
    char mp1[PATH_MAX];

    /*
     * We will need just one mount to start with using SMB 2
     */
    do_create_mount_path(mp1, sizeof(mp1), "testReadDirOfSymLinkMp1");

    error = mount_two_sessions(mp1, NULL, 0);
    if (error) {
        XCTFail("mount_two_sessions failed %d \n", error);
        goto done;
    }

    /* Create the test dirs */
    error = do_create_test_dirs(mp1);
    if (error) {
        XCTFail("do_create_test_dirs on <%s> failed %d:%s \n", mp1,
                error, strerror(error));
        goto done;
    }

    /* Set up file paths */
    strlcpy(dir_path, mp1, sizeof(dir_path));
    strlcat(dir_path, "/", sizeof(dir_path));
    strlcat(dir_path, cur_test_dir, sizeof(dir_path));

    strlcpy(test_dir_path, dir_path, sizeof(test_dir_path));
    strlcat(test_dir_path, "/", sizeof(test_dir_path));
    strlcat(test_dir_path, "test_directory", sizeof(test_dir_path));

    strlcpy(test_file_path, dir_path, sizeof(test_file_path));
    strlcat(test_file_path, "/", sizeof(test_file_path));
    strlcat(test_file_path, default_test_filename, sizeof(test_file_path));

    strlcpy(symlink_path, dir_path, sizeof(symlink_path));
    strlcat(symlink_path, "/", sizeof(symlink_path));
    strlcat(symlink_path, "test_sym_link", sizeof(symlink_path));

    /*
     * In mp1, we will create
     * 1. Directory, "test_directory"
     * 2. File, "testfile"
     * 3. Symbolic link to the file, "test_sym_link"
     */
    if (mkdir(test_dir_path, ALLPERMS) != 0) {
        XCTFail("mkdir on <%s> failed %d:%s \n", test_dir_path,
                errno, strerror(errno));
        goto done;
    }

    fd = open(test_file_path, oflag, S_IRWXU | S_IRWXG | S_IRWXO);
    if (fd == -1) {
        XCTFail("open on <%s> failed %d:%s \n", test_file_path,
                errno, strerror(errno));
        goto done;
    }

    /* Close file */
    error = close(fd);
    if (error) {
        XCTFail("close on fd failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        fd = -1;
    }

    /* Create the sym link to the file */
    error = symlink(test_file_path, symlink_path);
    if (error) {
        XCTFail("symlink on <%s> -> <%s> failed %d:%s \n",
                symlink_path, test_file_path, errno, strerror(errno));
        goto done;
    }

    /* Open the dir to be enumerated*/
    dirp = opendir(dir_path);
    if (dirp == NULL) {
        XCTFail("opendir on <%s> failed %d:%s \n",
                dir_path, errno, strerror(errno));
        goto done;
    }

    while ((dp = readdir(dirp)) != NULL) {
        if ((strcmp(dp->d_name, ".") == 0) || (strcmp(dp->d_name, "..") == 0)) {
            /* Skip . and .. */
            continue;
        }

        strlcpy(stat_path, mp1, sizeof(stat_path));
        strlcat(stat_path, "/", sizeof(stat_path));
        strlcat(stat_path, cur_test_dir, sizeof(stat_path));
        strlcat(stat_path, "/", sizeof(stat_path));
        strlcat(stat_path, dp->d_name, sizeof(stat_path));

        if (lstat(stat_path, &sb) != 0) {
            XCTFail("lstat on <%s> failed %d:%s \n", stat_path,
                    errno, strerror(errno));
            goto done;
        }

        printf("Checking <%s> \n", dp->d_name);
        item_count += 1;

        switch (sb.st_mode & S_IFMT) {
            case S_IFDIR:
                if (dp->d_type != DT_DIR) {
                    XCTFail("readdir type <octal %o> != lstat type <octal %o> for <%s> \n",
                            dp->d_type, sb.st_mode & S_IFMT, dp->d_name);
                    goto done;
                }
                break;

            case S_IFREG:
                if (dp->d_type != DT_REG) {
                    XCTFail("readdir type <octal %o> != lstat type <octal %o> for <%s> \n",
                            dp->d_type, sb.st_mode & S_IFMT, dp->d_name);
                    goto done;
                }
                break;

            case S_IFLNK:
                if (dp->d_type != DT_LNK) {
                    XCTFail("readdir type <octal %o> != lstat type <octal %o> for <%s> \n",
                            dp->d_type, sb.st_mode & S_IFMT, dp->d_name);
                    goto done;
                }
                break;

            default:
                XCTFail("Unexpected type for readdir type <octal %o>, lstat type <octal %o> for <%s> \n",
                        dp->d_type, sb.st_mode & S_IFMT, dp->d_name);
                goto done;
            }
    }
    (void)closedir(dirp);

    printf("Entry count <%d>\n", item_count);

    if (item_count != 3) {
        XCTFail("readdir did not find all three items, found only <%d> items \n",
                item_count);
        goto done;
    }

    /* Do the Delete on test dir */
    error = remove(test_dir_path);
    if (error) {
        fprintf(stderr, "do_delete on <%s> failed <%s (%d)>",
                test_dir_path, strerror(errno), errno);
        goto done;
    }

    /* Do the Delete on test file */
    error = remove(test_file_path);
    if (error) {
        fprintf(stderr, "do_delete on <%s> failed <%s (%d)>",
                test_file_path, strerror(errno), errno);
        goto done;
    }
    /* Do the Delete on sym link */
    error = remove(symlink_path);
    if (error) {
        fprintf(stderr, "do_delete on <%s> failed <%s (%d)>",
                symlink_path, strerror(errno), errno);
        goto done;
    }

    /*
     * If no errors, attempt to delete test dirs. This could fail if a
     * previous test failed and thats fine.
     */
    do_delete_test_dirs(mp1);

done:
    if (fd != -1) {
        /* Close file on mp1 */
        error = close(fd);
        if (error) {
            XCTFail("close on fd failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("unmount failed for first url %d\n", errno);
    }

    rmdir(mp1);
}

/*
 * Unit test for 67724462
 * 1. Open the file, fd1
 * 2. Write some data on fd1
 * 3. Open the file again, fd2
 * 4. Read the file and verify the data on fd2
 * 5. Close the file on fd2
 * 6. Close the file on fd1
 * 7. Open the file again, fd2
 * 8. Read the file and verify the data on fd2
 * 9. Close the file on fd2
 */
int openReadClose(const char *file_path, char *buffer, ssize_t buf_len)
{
    int error = 0, error2;
    int fd = -1;
    int oflag = O_RDONLY | O_NOFOLLOW;

    /*
     * Open the file on mp1
     */
    fd = open(file_path, oflag);
    if (fd == -1) {
        fprintf(stderr, "open on <%s> failed %d:%s \n", file_path,
                errno, strerror(errno));
        error = errno;
        goto done;
    }
    printf("File opened for read \n");

    error = read_and_verify(fd, buffer, buf_len);
    if (error) {
        goto done;
    }
    printf("Read verification passed \n");

done:
    if (fd != -1) {
        /* Close file on mp1 */
        error2 = close(fd);
        if (error2) {
            fprintf(stderr, "close on fd failed %d:%s \n",
                    error2, strerror(error2));
            if (error == 0) {
                error = error2;
            }
        }
        else {
            printf("File closed \n");
        }
    }

    return(error);
}

-(void)testUBCOpenWriteOpenReadClose
{
    int error = 0;
    char file_path[PATH_MAX];
    int fd = -1;
    int oflag = O_CREAT | O_RDWR | O_EXCL | O_TRUNC;
    char buffer[] = "abcd";
    ssize_t write_size;
    char mp1[PATH_MAX];

    /*
     * We will need just one mount to start with using SMB 2
     */
    do_create_mount_path(mp1, sizeof(mp1), "testUBCOpenWriteOpenReadCloseMp1");

    error = mount_two_sessions(mp1, NULL, 0);
    if (error) {
        XCTFail("mount_two_sessions failed %d \n", error);
        goto done;
    }

    /* Create the test dirs */
    error = do_create_test_dirs(mp1);
    if (error) {
        XCTFail("do_create_test_dirs on <%s> failed %d:%s \n", mp1,
                error, strerror(error));
        goto done;
    }

    /* Set up file path */
    strlcpy(file_path, mp1, sizeof(file_path));
    strlcat(file_path, "/", sizeof(file_path));
    strlcat(file_path, cur_test_dir, sizeof(file_path));
    strlcat(file_path, "/", sizeof(file_path));
    strlcat(file_path, default_test_filename, sizeof(file_path));

    /*
     * Open the file on mp1
     */
    fd = open(file_path, oflag, S_IRWXU | S_IRWXG | S_IRWXO);
    if (fd == -1) {
        XCTFail("open on <%s> failed %d:%s \n", file_path,
                errno, strerror(errno));
        goto done;
    }
    printf("File opened for read/write \n");

    /*
     * Write data to file on mp1
     */
    write_size = pwrite(fd, buffer, sizeof(buffer), 0);
    if (write_size != sizeof(buffer)) {
        XCTFail("data write failed %zd != %zd \n",
                write_size, sizeof(buffer));
        //error = EINVAL;
        goto done;
    }
    printf("Initial write passes \n");

    error = openReadClose(file_path, buffer, sizeof(buffer));
    if (error) {
        XCTFail("openReadClose on <%s> failed %d:%s \n", mp1,
                error, strerror(error));
        goto done;
    }
    printf("First openReadClose passes \n");

    /* Close file */
    error = close(fd);
    if (error) {
        XCTFail("close on fd failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        fd = -1;
        printf("File closed \n");
    }

    error = openReadClose(file_path, buffer, sizeof(buffer));
    if (error) {
        XCTFail("openReadClose on <%s> failed %d:%s \n", mp1,
                error, strerror(error));
        goto done;
    }
    printf("Second openReadClose passes \n");

    /* Do the Delete on test file */
    error = remove(file_path);
    if (error) {
        fprintf(stderr, "do_delete on <%s> failed <%s (%d)>",
                file_path, strerror(errno), errno);
        goto done;
    }

    /*
     * If no errors, attempt to delete test dirs. This could fail if a
     * previous test failed and thats fine.
     */
    do_delete_test_dirs(mp1);

done:
    if (fd != -1) {
        /* Close file on mp1 */
        error = close(fd);
        if (error) {
            XCTFail("close on fd failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("unmount failed for first url %d\n", errno);
    }

    rmdir(mp1);
}

/*
 * Another unit test for 67724462
 * 1. Open the file, fd1
 * 2. Write some data on fd1
 * 3. Close fd1 to save the last close mod date and data size
 * 4. Open the file again, fd1. This should check the last close date and size.
 * 5. Write some data on fd1 to change the size in UBC
 * 6. Open the file again, fd2. This should NOT check the last close date and size.
 * 7. Read the file and verify the data on fd2
 * 8. Close the file on fd2
 * 9. Close the file on fd1
 * 10. Open the file again, fd2
 * 11. Read the file and verify the data on fd2
 * 12. Close the file on fd2
 */
-(void)testUBCOpenWriteCloseOpenWriteOpenRead
{
    int error = 0;
    char file_path[PATH_MAX];
    int fd = -1;
    char buffer[] = "abcd";
    char buffer2[] = "efghijkl";
    ssize_t write_size;
    char mp1[PATH_MAX];

    /*
     * We will need just one mount to start with using SMB 2
     */
    do_create_mount_path(mp1, sizeof(mp1), "testUBCOpenWriteCloseOpenWriteOpenReadMp1");

    error = mount_two_sessions(mp1, NULL, 0);
    if (error) {
        XCTFail("mount_two_sessions failed %d \n", error);
        goto done;
    }

    /* Create the test dirs */
    error = do_create_test_dirs(mp1);
    if (error) {
        XCTFail("do_create_test_dirs on <%s> failed %d:%s \n", mp1,
                error, strerror(error));
        goto done;
    }

    /* Set up file path */
    strlcpy(file_path, mp1, sizeof(file_path));
    strlcat(file_path, "/", sizeof(file_path));
    strlcat(file_path, cur_test_dir, sizeof(file_path));
    strlcat(file_path, "/", sizeof(file_path));
    strlcat(file_path, default_test_filename, sizeof(file_path));

    /*
     * Open the file on mp1
     */
    fd = open(file_path, O_CREAT | O_RDWR | O_EXCL | O_TRUNC, S_IRWXU | S_IRWXG | S_IRWXO);
    if (fd == -1) {
        XCTFail("open on <%s> failed %d:%s \n", file_path,
                errno, strerror(errno));
        goto done;
    }
    printf("File opened for read/write \n");

    /*
     * Write data to file on mp1
     */
    write_size = pwrite(fd, buffer, sizeof(buffer), 0);
    if (write_size != sizeof(buffer)) {
        XCTFail("data write failed %zd != %zd \n",
                write_size, sizeof(buffer));
        //error = EINVAL;
        goto done;
    }
    printf("Initial write passes \n");
    
    /* Close file */
    error = close(fd);
    if (error) {
        XCTFail("close on fd failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        //fd = -1;
        printf("File closed \n");
    }

    /* At this point the last close mod date and data size are saved */
    
    /*
     * Open the file on mp1 again. The last close mod date and data size
     * will get checked and nothing has changed so UBC stays valid.
     */
    fd = open(file_path, O_RDWR);
    if (fd == -1) {
        XCTFail("open on <%s> failed %d:%s \n", file_path,
                errno, strerror(errno));
        goto done;
    }
    printf("File opened again for read/write \n");

    /*
     * Write different data to file on mp1
     */
    write_size = pwrite(fd, buffer2, sizeof(buffer2), 0);
    if (write_size != sizeof(buffer2)) {
        XCTFail("data write failed %zd != %zd \n",
                write_size, sizeof(buffer2));
        //error = EINVAL;
        goto done;
    }
    printf("Second write passes \n");

    /*
     * This next Open should NOT check the mod date and data size since its
     * not the first open call on the file.
     */
    error = openReadClose(file_path, buffer2, sizeof(buffer2));
    if (error) {
        XCTFail("openReadClose on <%s> failed %d:%s \n", mp1,
                error, strerror(error));
        goto done;
    }
    printf("First openReadClose passes \n");

    /* Close file */
    error = close(fd);
    if (error) {
        XCTFail("close on fd failed %d:%s \n", errno, strerror(errno));
        goto done;
    }
    else {
        fd = -1;
        printf("File closed \n");
    }

    error = openReadClose(file_path, buffer2, sizeof(buffer2));
    if (error) {
        XCTFail("openReadClose on <%s> failed %d:%s \n", mp1,
                error, strerror(error));
        goto done;
    }
    printf("Second openReadClose passes \n");

    /* Do the Delete on test file */
    error = remove(file_path);
    if (error) {
        fprintf(stderr, "do_delete on <%s> failed <%s (%d)>",
                file_path, strerror(errno), errno);
        goto done;
    }

    /*
     * If no errors, attempt to delete test dirs. This could fail if a
     * previous test failed and thats fine.
     */
    do_delete_test_dirs(mp1);

done:
    if (fd != -1) {
        /* Close file on mp1 */
        error = close(fd);
        if (error) {
            XCTFail("close on fd failed %d:%s \n", errno, strerror(errno));
        }
    }

    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("unmount failed for first url %d\n", errno);
    }

    rmdir(mp1);
}


#define MAX_URL_TO_DICT_TO_URL_TEST 12

struct urlToDictToURLStrings {
    const char *url;
    const CFStringRef EscapedHost;
    const CFStringRef EscapedShare;
};

struct urlToDictToURLStrings urlToDictToURL[] = {
    /* Make sure IPv6 addresses are handled in host */
    { "smb://local1:local@[fe80::d9b6:f149:a17c:8307%25en1]/Vista-Share", CFSTR("[fe80::d9b6:f149:a17c:8307%en1]"), CFSTR("Vista-Share") },

    /* Make sure escaped chars in host are handled */
    { "smb://local:local@colley%5B3%5D._smb._tcp.local/local", CFSTR("colley[3]._smb._tcp.local"), CFSTR("local") },

    /* Make sure escaped chars in user name are handled */
    { "smb://BAD%3A%3B%2FBAD@colley2/badbad", CFSTR("colley2"), CFSTR("badbad") },

    /* Make sure escaped chars in host are handled */
    { "smb://user:password@%7e%21%40%24%3b%27%28%29/share", CFSTR("~!@$;'()"), CFSTR("share") },

    /* Make sure we handle a "/" in share name */
    { "smb://server.local/Open%2fSpace", CFSTR("server.local"), CFSTR("Open%2FSpace") },

    /* Make sure we handle "%" in share name */
    { "smb://server.local/Odd%25ShareName", CFSTR("server.local"), CFSTR("Odd%ShareName") },
    
    /* Make sure we handle share name of just "/" */
    { "smb://server.local/%2f", CFSTR("server.local"), CFSTR("%2F") },
    
    /* Make sure we handle a "/" and a "%" in share name */
    { "smb://server.local/Odd%2fShare%25Name", CFSTR("server.local"), CFSTR("Odd%2FShare%Name") },
    
    /* Make sure we handle all URL reserved chars of " !#$%&'()*+,:;<=>?@[]|" in share name */
    { "smb://server.local/%20%21%23%24%25%26%27%28%29%2a%2b%2c%3a%3b%3c%3d%3e%3f%40%5b%5d%7c", CFSTR("server.local"), CFSTR(" !#$%&'()*+,:;<=>?@[]|") },
    
    /* Make sure we handle all URL reserved chars of " !#$%&'()*+,:;<=>?@[]|" in path */
    { "smb://server.local/share/%20%21%23%24%25%26%27%28%29%2a%2b%2c%3a%3b%3c%3d%3e%3f%40%5b%5d%7c", CFSTR("server.local"), CFSTR("share/ !#$%&'()*+,:;<=>?@[]|") },
    
    /* Make sure workgroup;user round trips correctly */
    { "smb://foo;bar@server.local/share", CFSTR("server.local"), CFSTR("share") },

    /* Make sure alternate port round trips correctly */
    { "smb://foo@server.local:446/share", CFSTR("server.local"), CFSTR("share") },

    { NULL, NULL, NULL }
};

-(void)testURLToDictToURL
{
    /*
     * This tests round tripping from smb_url_to_dictionary()
     * and smb_dictionary_to_url()
     *
     * It also checks that host and share are escaped properly
     */
    CFURLRef startURL, endURL;
    CFDictionaryRef dict;
    int ii, error = 0;
    CFStringRef host = NULL;
    CFStringRef share = NULL;

    for (ii = 0; ii < MAX_URL_TO_DICT_TO_URL_TEST; ii++) {
        startURL = CreateSMBURL(urlToDictToURL[ii].url);
        if (!startURL) {
            error = errno;
            XCTFail("CreateSMBURL with <%s> failed, %d\n",
                    urlToDictToURL[ii].url, error);
            break;
        }
        
        /* Convert CFURL to a dictionary */
        error = smb_url_to_dictionary(startURL, &dict);
        if (error) {
            XCTFail("smb_url_to_dictionary with <%s> failed, %d\n",
                    urlToDictToURL[ii].url, error);

            CFRelease(startURL);
            break;
        }
        
        /* Get the host from the dictionary */
        host = CFDictionaryGetValue(dict, kNetFSHostKey);
        if (host == NULL) {
            XCTFail("Failed to find host in dictionary for <%s> \n",
                    urlToDictToURL[ii].url);
            CFShow(dict);
            CFShow(startURL);

            CFRelease(dict);
            CFRelease(startURL);
            break;
        }
        
        /* Verify the host is escaped out correctly */
        if (kCFCompareEqualTo == CFStringCompare (host,
                                                  urlToDictToURL[ii].EscapedHost,
                                                  kCFCompareCaseInsensitive)) {
            printf("Host in dictionary is correct for <%s> \n",
                   urlToDictToURL[ii].url);
        }
        else {
            XCTFail("Host in dictionary did not match for <%s> \n",
                    urlToDictToURL[ii].url);
            CFShow(dict);
            CFShow(urlToDictToURL[ii].EscapedHost);

            CFRelease(dict);
            CFRelease(startURL);
            break;
        }

        /* Get the share from the dictionary */
        share = CFDictionaryGetValue(dict, kNetFSPathKey);
        if (share == NULL) {
            XCTFail("Failed to find share in dictionary for <%s> \n",
                    urlToDictToURL[ii].url);
            CFShow(dict);
            CFShow(startURL);

            CFRelease(dict);
            CFRelease(startURL);
            break;
        }
        
        /* Verify the share is escaped out correctly */
        if (kCFCompareEqualTo == CFStringCompare (share, urlToDictToURL[ii].EscapedShare,
                                                  kCFCompareCaseInsensitive)) {
            printf("Share in dictionary is correct for <%s> \n",
                   urlToDictToURL[ii].url);
        }
        else {
            XCTFail("Share in dictionary did not match for <%s> \n",
                    urlToDictToURL[ii].url);
            CFShow(dict);
            CFShow(urlToDictToURL[ii].EscapedShare);

            CFRelease(dict);
            CFRelease(startURL);
            break;
        }
        
        error = smb_dictionary_to_url(dict, &endURL);
        if (error) {
            XCTFail("smb_dictionary_to_url with <%s> failed, %d\n", urlToDictToURL[ii].url,  error);
            CFShow(dict);
            CFShow(startURL);

            CFRelease(dict);
            CFRelease(startURL);
            break;
        }
        /* We only want to compare the URL string currently, may want to add more later */
        if (CFStringCompare(CFURLGetString(startURL), CFURLGetString(endURL),
                            kCFCompareCaseInsensitive) != kCFCompareEqualTo) {
            XCTFail("Round trip failed for <%s>\n", urlToDictToURL[ii].url);
            CFShow(dict);
            CFShow(startURL);
            CFShow(endURL);
            
            CFRelease(dict);
            CFRelease(startURL);
            CFRelease(endURL);
            break;
        }

        printf("Round trip was successful for <%s> \n", urlToDictToURL[ii].url);

        CFRelease(dict);
        CFRelease(startURL);
        CFRelease(endURL);
    }
}


#define MAX_URL_TO_DICT_TEST 8

struct urlToDictStrings {
    const char *url;
    const CFStringRef userAndDomain;
    const CFStringRef password;
    const CFStringRef host;
    const CFStringRef port;
    const CFStringRef path;
};

struct urlToDictStrings urlToDict[] = {
    /* Just server, .local server name */
    { "smb://server.local", NULL, NULL, CFSTR("server.local"), NULL, NULL },

    /* Empty user name, dns server name */
    { "smb://@netfs-13.apple.com", CFSTR(""), NULL, CFSTR("netfs-13.apple.com"), NULL, NULL },

    /* Empty domain and username, netbios server name */
    { "smb://;@Windoze2016", CFSTR(""), NULL, CFSTR("Windoze2016"), NULL, NULL },

    /* Empty domain, username and password, Bonjour server name */
    { "smb://;:@User's%20Macintosh._smb._tcp.local", CFSTR(""), CFSTR(""), CFSTR("User's Macintosh._smb._tcp.local"), NULL, NULL },

    /* Guest login with no password, IPv4 server name */
    { "smb://guest:@192.168.1.30/", CFSTR("guest"), CFSTR(""), CFSTR("192.168.1.30"), NULL, NULL },

    /* Workgroup, user and password. Note the "\\" instead of the ";", IPv6 server */
    { "smb://workgroup;foo:bar@[fe80::d9b6:f149:a17c:8307%25en1]", CFSTR("workgroup\\foo"), CFSTR("bar"), CFSTR("[fe80::d9b6:f149:a17c:8307%en1]"), NULL, NULL },

    /* Check for alternate port, dns server name with port */
    { "smb://workgroup;foo:bar@server.local:446", CFSTR("workgroup\\foo"), CFSTR("bar"), CFSTR("server.local"), CFSTR("446"), NULL },

    /* Check for path, IPv4 server with port */
    { "smb://workgroup;foo:bar@192.168.1.30:446/share", CFSTR("workgroup\\foo"), CFSTR("bar"), CFSTR("192.168.1.30"), CFSTR("446"), CFSTR("share") },

    { NULL, NULL, NULL }
};

-(void)testURLToDict
{
    /*
     * This tests smb_url_to_dictionary() fills in the dictionary correctly
     */
    CFURLRef startURL;
    CFDictionaryRef dict;
    int ii, error = 0;
    CFStringRef userAndDomain = NULL;
    CFStringRef password = NULL;
    CFStringRef host = NULL;
    CFStringRef port = NULL;
    CFStringRef path = NULL;

    for (ii = 0; ii < MAX_URL_TO_DICT_TEST; ii++) {
        startURL = CreateSMBURL(urlToDict[ii].url);
        if (!startURL) {
            error = errno;
            XCTFail("CreateSMBURL with <%s> failed, %d\n",
                    urlToDict[ii].url, error);
            break;
        }
        
        /* Convert CFURL to a dictionary */
        error = smb_url_to_dictionary(startURL, &dict);
        if (error) {
            XCTFail("smb_url_to_dictionary with <%s> failed, %d\n",
                    urlToDict[ii].url, error);

            CFRelease(startURL);
            break;
        }
        
        /* Get the domain and user from the dictionary */
        userAndDomain = CFDictionaryGetValue(dict, kNetFSUserNameKey);
        if (urlToDict[ii].userAndDomain == NULL) {
            /* We expect no user name to be found */
            if (userAndDomain != NULL) {
                XCTFail("Username should have been NULL with <%s> \n",
                        urlToDict[ii].url);
                CFShow(dict);
                CFShow(userAndDomain);
                
                CFRelease(startURL);
                CFRelease(dict);
                break;
            }
            else {
                printf("Username in dictionary is NULL as expected for <%s> \n",
                       urlToDict[ii].url);
            }
        }
        else {
            /* Verify that user name matches */
            if (userAndDomain == NULL) {
                XCTFail("Failed to find Username in dictionary for <%s> \n",
                        urlToDict[ii].url);
                CFShow(dict);

                CFRelease(dict);
                CFRelease(startURL);
                break;
            }

            if (kCFCompareEqualTo == CFStringCompare (userAndDomain,
                                                      urlToDict[ii].userAndDomain,
                                                      kCFCompareCaseInsensitive)) {
                printf("Username in dictionary is correct for <%s> \n",
                       urlToDict[ii].url);
            }
            else {
                XCTFail("Username in dictionary did not match for <%s> \n",
                        urlToDict[ii].url);
                CFShow(dict);
                CFShow(urlToDict[ii].userAndDomain);

                CFRelease(dict);
                CFRelease(startURL);
                break;
            }
        }
        
        /* Get the password from the dictionary */
        password = CFDictionaryGetValue(dict, kNetFSPasswordKey);
        if (urlToDict[ii].password == NULL) {
            /* We expect no password to be found */
            if (password != NULL) {
                XCTFail("Password should have been NULL with <%s> \n",
                        urlToDict[ii].url);
                CFShow(dict);
                CFShow(password);
                
                CFRelease(startURL);
                CFRelease(dict);
                break;
            }
            else {
                printf("Password in dictionary is NULL as expected for <%s> \n",
                       urlToDict[ii].url);
            }
        }
        else {
            /* Verify that password matches */
            if (password == NULL) {
                XCTFail("Failed to find Password in dictionary for <%s> \n",
                        urlToDict[ii].url);
                CFShow(dict);

                CFRelease(dict);
                CFRelease(startURL);
                break;
            }

            if (kCFCompareEqualTo == CFStringCompare (password,
                                                      urlToDict[ii].password,
                                                      kCFCompareCaseInsensitive)) {
                printf("Password in dictionary is correct for <%s> \n",
                       urlToDict[ii].url);
            }
            else {
                XCTFail("Password in dictionary did not match for <%s> \n",
                        urlToDict[ii].url);
                CFShow(dict);
                CFShow(urlToDict[ii].password);

                CFRelease(dict);
                CFRelease(startURL);
                break;
            }
        }

        /* Get the host from the dictionary */
        host = CFDictionaryGetValue(dict, kNetFSHostKey);
        if (host == NULL) {
            XCTFail("Failed to find host in dictionary for <%s> \n",
                    urlToDict[ii].url);
            CFShow(dict);

            CFRelease(dict);
            CFRelease(startURL);
            break;
        }
        
        /* Verify that host matches */
        if (kCFCompareEqualTo == CFStringCompare (host,
                                                  urlToDict[ii].host,
                                                  kCFCompareCaseInsensitive)) {
            printf("Host in dictionary is correct for <%s> \n",
                   urlToDict[ii].url);
        }
        else {
            XCTFail("Host in dictionary did not match for <%s> \n",
                    urlToDict[ii].url);
            CFShow(dict);
            CFShow(urlToDict[ii].host);

            CFRelease(dict);
            CFRelease(startURL);
            break;
        }

        /* Get the port from the dictionary */
        port = CFDictionaryGetValue(dict, kNetFSAlternatePortKey);
        if (urlToDict[ii].port == NULL) {
            /* We expect no port to be found */
            if (port != NULL) {
                XCTFail("Port should have been NULL with <%s> \n",
                        urlToDict[ii].url);
                CFShow(dict);
                CFShow(port);
                
                CFRelease(startURL);
                CFRelease(dict);
                break;
            }
            else {
                printf("Port in dictionary is NULL as expected for <%s> \n",
                       urlToDict[ii].url);
            }
        }
        else {
            /* Verify that port matches */
            if (port == NULL) {
                XCTFail("Failed to find Port in dictionary for <%s> \n",
                        urlToDict[ii].url);
                CFShow(dict);

                CFRelease(dict);
                CFRelease(startURL);
                break;
            }

            if (kCFCompareEqualTo == CFStringCompare (port,
                                                      urlToDict[ii].port,
                                                      kCFCompareCaseInsensitive)) {
                printf("Port in dictionary is correct for <%s> \n",
                       urlToDict[ii].url);
            }
            else {
                XCTFail("Port in dictionary did not match for <%s> \n",
                        urlToDict[ii].url);
                CFShow(dict);
                CFShow(urlToDict[ii].port);

                CFRelease(dict);
                CFRelease(startURL);
                break;
            }
        }

        /* Get the path from the dictionary */
        path = CFDictionaryGetValue(dict, kNetFSPathKey);
        if (urlToDict[ii].path == NULL) {
            /* We expect no path to be found */
            if (path != NULL) {
                XCTFail("Path should have been NULL with <%s> \n",
                        urlToDict[ii].url);
                CFShow(dict);
                CFShow(path);
                
                CFRelease(startURL);
                CFRelease(dict);
                break;
            }
            else {
                printf("Path in dictionary is NULL as expected for <%s> \n",
                       urlToDict[ii].url);
            }
        }
        else {
            /* Verify that port matches */
            if (path == NULL) {
                XCTFail("Failed to find Path in dictionary for <%s> \n",
                        urlToDict[ii].url);
                CFShow(dict);

                CFRelease(dict);
                CFRelease(startURL);
                break;
            }

            if (kCFCompareEqualTo == CFStringCompare (path,
                                                      urlToDict[ii].path,
                                                      kCFCompareCaseInsensitive)) {
                printf("Path in dictionary is correct for <%s> \n",
                       urlToDict[ii].url);
            }
            else {
                XCTFail("Path in dictionary did not match for <%s> \n",
                        urlToDict[ii].url);
                CFShow(dict);
                CFShow(urlToDict[ii].path);

                CFRelease(dict);
                CFRelease(startURL);
                break;
            }
        }
        
        printf("URL to dictionary was successful for <%s> \n", urlToDict[ii].url);

        CFRelease(dict);
        CFRelease(startURL);
    }
}

-(void)testListSharesOnce
{
    /*
     * This tests SMBNetFsCreateSessionRef, SMBNetFsOpenSession and
     * smb_netshareenum works.
     */
    CFURLRef url = NULL;
    SMBHANDLE serverConnection = NULL;
    int error;
    CFMutableDictionaryRef OpenOptions = NULL;
    CFDictionaryRef shares = NULL;
    
    error = SMBNetFsCreateSessionRef(&serverConnection);
    if (error) {
        XCTFail("SMBNetFsCreateSessionRef failed %d for <%s>\n",
                error, g_test_url1);
        goto done;
    }
    
    url = CreateSMBURL(g_test_url1);
    if (!url) {
        error = errno;
        XCTFail("CreateSMBURL failed %d for <%s>\n",
                error, g_test_url1);
        goto done;
    }
    
    OpenOptions = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks);
    if (OpenOptions == NULL) {
        error = errno;
        XCTFail("CFDictionaryCreateMutable failed %d for <%s>\n",
                error, g_test_url1);
        goto done;
    }
    
    error = SMBNetFsOpenSession(url, serverConnection, OpenOptions, NULL);
    if (error) {
        XCTFail("SMBNetFsOpenSession failed %d for <%s>\n",
                error, g_test_url1);
        goto done;
    }
    
    error = smb_netshareenum(serverConnection, &shares, FALSE);
    if (error) {
        XCTFail("smb_netshareenum failed %d for <%s>\n",
                error, g_test_url1);
        goto done;
    }

    CFShow(shares);
    printf("List shares was successful for <%s> \n", g_test_url1);

done:
    if (url) {
        CFRelease(url);
    }
    
    if (OpenOptions) {
        CFRelease(OpenOptions);
    }
    
    if (shares) {
        CFRelease(shares);
    }
    
    if (serverConnection) {
        SMBNetFsCloseSession(serverConnection);
    }
}


#define MAX_NUMBER_TESTSTRING 6

#define TESTSTRING1 "/George/J\\im/T:?.*est"
#define TESTSTRING2 "/George/J\\im/T:?.*est/"
#define TESTSTRING3 "George/J\\im/T:?.*est/"
#define TESTSTRING4 "George/J\\im/T:?.*est"
#define TESTSTRING5 "George"
#define TESTSTRING6 "/"
#define TESTSTRING7 "/George"

const char *teststr[MAX_NUMBER_TESTSTRING] = {TESTSTRING1, TESTSTRING2, TESTSTRING3, TESTSTRING4, TESTSTRING5, TESTSTRING6 };
const char *testslashstr[MAX_NUMBER_TESTSTRING] = {TESTSTRING1, TESTSTRING2, TESTSTRING2, TESTSTRING1, TESTSTRING7, TESTSTRING6 };

static int test_path(struct smb_ctx *ctx, const char *instring, const char *comparestring, uint32_t flags)
{
    char utf8str[1024];
    char ntwrkstr[1024];
    size_t ntwrk_len = 1024;
    size_t utf8_len = 1024;

    printf("\nTesting string  %s\n", instring);
    
    ntwrk_len = 1024;
    memset(ntwrkstr, 0, 1024);
    if (smb_localpath_to_ntwrkpath(ctx, instring, strlen(instring), ntwrkstr, &ntwrk_len, flags)) {
        printf("smb_localpath_to_ntwrkpath: %s failed %d\n", instring, errno);
        return -1;
    }

    //smb_ctx_hexdump(__FUNCTION__, "network name  =", (u_char *)ntwrkstr, ntwrk_len);
    
    memset(utf8str, 0, 1024);
    if (smb_ntwrkpath_to_localpath(ctx, ntwrkstr, ntwrk_len, utf8str, &utf8_len, flags)) {
        printf("smb_ntwrkpath_to_localpath: %s failed %d\n", instring, errno);
        return -1;
    }
    
    if (strcmp(comparestring, utf8str) != 0) {
        printf("UTF8 string didn't match: %s != %s\n", instring, utf8str);
        return -1;
    }

    printf("utf8str = %s len = %ld\n", utf8str, utf8_len);
    return 0;
}

static int test_path_conversion(struct smb_ctx *ctx)
{
    int ii, failcnt = 0, passcnt = 0;
    int maxcnt = MAX_NUMBER_TESTSTRING;
    uint32_t flags = SMB_UTF_SFM_CONVERSIONS;
    
    for (ii = 0; ii < maxcnt; ii++) {
        if (test_path(ctx, teststr[ii], teststr[ii], flags) == -1) {
            failcnt++;
        }
        else {
            passcnt++;
        }
    }
    
    flags |= SMB_FULLPATH_CONVERSIONS;
    for (ii = 0; ii < maxcnt; ii++) {
        if (test_path(ctx, teststr[ii], testslashstr[ii], flags) == -1) {
            failcnt++;
        }
        else {
            passcnt++;
        }
    }

    printf("test_path_conversion: Total = %d Passed = %d Failed = %d\n",
           (maxcnt * 2), passcnt, failcnt);

    return (failcnt) ? EIO : 0;
}

-(void)testNameConversion
{
    /*
     * This tests round tripping from smb_localpath_to_ntwrkpath()
     * and smb_ntwrkpath_to_localpath()
     */
    CFURLRef url = NULL;
    void *ref = NULL;
    int error = 0;
    CFMutableDictionaryRef OpenOptions = NULL;
    CFStringRef urlString = NULL;
    
    url = CreateSMBURL(g_test_url1);
    if (!url) {
        error = errno;
        XCTFail("CreateSMBURL failed %d for <%s>\n",
                error, g_test_url1);
        goto done;
    }

    OpenOptions = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks);
    if (OpenOptions == NULL) {
        error = errno;
        XCTFail("CFDictionaryCreateMutable failed %d for <%s>\n",
                error, g_test_url1);
        goto done;
    }
    
    ref = create_smb_ctx();
    if (ref == NULL) {
        error = errno;
        XCTFail("create_smb_ctx failed %d for <%s>\n",
                error, g_test_url1);
        goto done;
    }
    
    error = smb_open_session(ref, url, OpenOptions, NULL);
    if (error) {
        XCTFail("smb_open_session failed %d for <%s>\n",
                error, g_test_url1);
        goto done;
    }
    
    error = test_path_conversion((struct smb_ctx *)ref);
    if (error) {
        XCTFail("test_path_conversion failed %d for <%s>\n",
                error, g_test_url1);
        goto done;
    }

done:
    if (OpenOptions)
        CFRelease(OpenOptions);
    if (urlString)
        CFRelease(urlString);
    if (url)
        CFRelease(url);

    smb_ctx_done(ref);
}

-(void)testSMBOpenServerWithMountPoint
{
    /*
     * This tests testSMBOpenServerWithMountPoint works.
     */
    SMBHANDLE mpConnection = NULL;
    SMBHANDLE shareConnection = NULL;
    int error = 0;
    uint32_t status = 0;
    CFDictionaryRef shares = NULL;
    char mp1[PATH_MAX];
    
    do_create_mount_path(mp1, sizeof(mp1), "testSMBOpenServerWithMountPointMp1");

    /* First mount a volume */
    if ((mkdir(mp1, S_IRWXU | S_IRWXG) == -1) && (errno != EEXIST)) {
        error = errno;
        XCTFail("mkdir failed %d for <%s>\n",
                error, g_test_url1);
        goto done;
    }
    
    status = SMBOpenServerEx(g_test_url1, &mpConnection,
                             kSMBOptionNoPrompt | kSMBOptionSessionOnly);
    if (!NT_SUCCESS(status)) {
        XCTFail("SMBOpenServerEx failed 0x%x for <%s>\n",
                status, g_test_url1);
        goto done;
    }
    
    status = SMBMountShareEx(mpConnection, NULL, mp1, 0, 0, 0, 0, NULL, NULL);
    if (!NT_SUCCESS(status)) {
        XCTFail("SMBMountShareEx failed 0x%x for <%s>\n",
                status, g_test_url1);
        goto done;
    }
    
    /* Now that we have a mounted volume we run the real test */
    status = SMBOpenServerWithMountPoint(mp1, "IPC$",
                                         &shareConnection, 0);
    if (!NT_SUCCESS(status)) {
        XCTFail("SMBMountShareEx failed 0x%x for <%s>\n",
                status, g_test_url1);
        goto done;
    }
    
    error = smb_netshareenum(shareConnection, &shares, FALSE);
    if (error == 0) {
        CFShow(shares);
        printf("SMBOpenServerWithMountPoint() and list shares was successful for <%s> \n",
               g_test_url1);
    }
    
    if (shares) {
        CFRelease(shares);
    }
 
done:
    /* Now cleanup everything */
    if (shareConnection) {
        SMBReleaseServer(shareConnection);
    }
    
    if (mpConnection) {
        SMBReleaseServer(mpConnection);
    }
    
    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("unmount failed %d\n", errno);
    }
}

#define MAX_SID_PRINTBUFFER    256    /* Used to print out the sid in case of an error */

static
void print_ntsid(ntsid_t *sidptr, const char *printstr)
{
    char sidprintbuf[MAX_SID_PRINTBUFFER];
    char *s = sidprintbuf;
    int subs;
    uint64_t auth = 0;
    unsigned i;
    uint32_t *ip;
    size_t len;
    
    bzero(sidprintbuf, MAX_SID_PRINTBUFFER);
    for (i = 0; i < sizeof(sidptr->sid_authority); i++) {
        auth = (auth << 8) | sidptr->sid_authority[i];
    }
    s += snprintf(s, MAX_SID_PRINTBUFFER, "S-%u-%llu", sidptr->sid_kind, auth);
    
    subs = sidptr->sid_authcount;
    
    for (ip = sidptr->sid_authorities; subs--; ip++)  {
        len = MAX_SID_PRINTBUFFER - (s - sidprintbuf);
        s += snprintf(s, len, "-%u", *ip);
    }
    
    fprintf(stdout, "%s: sid = %s \n", printstr, sidprintbuf);
}

-(void)testAccountNameSID
{
    /*
     * This tests that LSAR DCE/RPC works.
     */
    ntsid_t *sid = NULL;
    SMBHANDLE serverConnection = NULL;
    uint64_t options = kSMBOptionAllowGuestAuth | kSMBOptionAllowAnonymousAuth;
    uint32_t status = 0;
    SMBServerPropertiesV1 properties;
    char *AccountName = NULL, *DomainName = NULL;
    int error;

    status = SMBOpenServerEx(g_test_url1, &serverConnection, options);
    if (!NT_SUCCESS(status)) {
        error = errno;
        XCTFail("SMBOpenServerEx failed %d for <%s>\n",
                error, g_test_url1);
        return;
    }
    status = SMBGetServerProperties(serverConnection, &properties, kPropertiesVersion, sizeof(properties));
    if (!NT_SUCCESS(status)) {
        error = errno;
        XCTFail("SMBGetServerProperties failed %d for <%s>\n",
                error, g_test_url1);
        return;
    }

    status = GetNetworkAccountSID(properties.serverName, &AccountName, &DomainName, &sid);
    if (!NT_SUCCESS(status)) {
        error = errno;
        XCTFail("GetNetworkAccountSID failed %d for <%s>\n",
                error, g_test_url1);
        return;
    }
    
    if (serverConnection) {
        SMBReleaseServer(serverConnection);
    }

    printf("user = %s domain = %s\n", AccountName, DomainName);
    print_ntsid(sid, "Network Users ");

    if (sid) {
        free(sid);
    }
    
    if (AccountName) {
        free(AccountName);
    }
    
    if (DomainName) {
        free(DomainName);
    }
}

static int do_mount_URL(const char *mp, CFURLRef url, CFDictionaryRef openOptions, int mntflags)
{
    SMBHANDLE theConnection = NULL;
    CFStringRef mountPoint = NULL;
    CFDictionaryRef mountInfo = NULL;
    int error;
    CFNumberRef numRef = NULL;
    CFMutableDictionaryRef mountOptions = NULL;
    
    if ((mkdir(mp, S_IRWXU | S_IRWXG) == -1) && (errno != EEXIST)) {
        return errno;
    }

    error = SMBNetFsCreateSessionRef(&theConnection);
    if (error) {
        return error;
    }
    
    error = SMBNetFsOpenSession(url, theConnection, openOptions, NULL);
    if (error) {
        (void)SMBNetFsCloseSession(theConnection);
        return error;
    }
    
    mountOptions = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                             &kCFTypeDictionaryKeyCallBacks,
                                             &kCFTypeDictionaryValueCallBacks);
    if (!mountOptions) {
        (void)SMBNetFsCloseSession(theConnection);
        return error;
    }
    
    numRef = CFNumberCreate(nil, kCFNumberIntType, &mntflags);
    if (numRef) {
        CFDictionarySetValue( mountOptions, kNetFSMountFlagsKey, numRef);
        CFRelease(numRef);
    }
    
    mountPoint = CFStringCreateWithCString(kCFAllocatorDefault, mp,
                                           kCFStringEncodingUTF8);
    if (mountPoint) {
        error = SMBNetFsMount(theConnection, url, mountPoint, mountOptions, &mountInfo, NULL, NULL);
        CFRelease(mountPoint);
        if (mountInfo) {
            CFRelease(mountInfo);
        }
    }
    else {
        error = ENOMEM;
    }
    
    CFRelease(mountOptions);
    (void)SMBNetFsCloseSession(theConnection);
    return error;
}

-(void)testMountExists
{
    int error;
    int do_unmount1 = 0;
    int do_unmount2 = 0;
    char mp1[PATH_MAX];
    char mp2[PATH_MAX];

    /*
     * <80936007> Need to do forced unmounts because Spotlight tends to
     * get into the mount which causes a normal unmount to return EBUSY.
     */
    
    do_create_mount_path(mp1, sizeof(mp1), "testMountExistsMp1");
    do_create_mount_path(mp2, sizeof(mp2), "testMountExistsMp2");

    /* Test one: mount no browse twice */
    printf("Test 1: mount twice with MNT_DONTBROWSE. Second mount should get EEXIST error. \n");
    
    error = do_mount_URL(mp1, urlRef1, NULL, MNT_DONTBROWSE);
    if (error) {
        XCTFail("TEST 1 mntFlags = MNT_DONTBROWSE: Couldn't mount first volume: shouldn't happen %d\n", error);
        goto done;
    }
    do_unmount1 = 1;
    
    error = do_mount_URL(mp2, urlRef1, NULL, MNT_DONTBROWSE);
    if (error != EEXIST) {
        XCTFail("TEST 1, mntFlags = MNT_DONTBROWSE: Second volume returned wrong error: %d\n", error);
        
        /* If second mount somehow succeeded, try to unmount it now. */
        if ((error == 0) && (unmount(mp2, MNT_FORCE) == -1)) {
            XCTFail("TEST 1 unmount mp2 failed %d\n", errno);
            /* try force unmount on exit */
            do_unmount2 = 1;
        }
        goto done;
    }
    
    /* Try unmount of mp1 */
    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("TEST 1 unmount mp1 failed %d\n", errno);
        goto done;
    }
    do_unmount1 = 0;
    
    
    /* Test two: mount first no browse second browse */
    printf("Test 2: mount first with MNT_DONTBROWSE then second mount with browse \n");

    error = do_mount_URL(mp1, urlRef1, NULL, MNT_DONTBROWSE);
    if (error) {
        XCTFail("TEST 2, mntFlags = MNT_DONTBROWSE: Couldn't mount first volume: shouldn't happen %d\n", error);
        goto done;
    }
    do_unmount1 = 1;

    error = do_mount_URL(mp2, urlRef1, NULL, 0);
    if (error != 0) {
        XCTFail("TEST 2, mntFlags = 0: Second volume return wrong error: %d\n", error);
        goto done;
    }
    do_unmount2 = 1;

    /* Try unmount of mp1 */
   if (unmount(mp1, MNT_FORCE) == -1) {
       XCTFail("TEST 2 unmount mp1 failed %d\n", errno);
       goto done;
    }
    do_unmount1 = 0;

    /* Try unmount of mp2 */
   if (unmount(mp2, MNT_FORCE) == -1) {
       XCTFail("TEST 2 unmount mp2 failed %d\n", errno);
       goto done;
    }
    do_unmount2 = 0;

    
    /* Test three: mount first browse second no browse */
    printf("Test 3: mount first with browse then second mount with MNT_DONTBROWSE \n");

    error = do_mount_URL(mp1, urlRef1, NULL, 0);
    if (error) {
        XCTFail("TEST 3, mntFlags = 0: Couldn't mount first volume: shouldn't happen %d\n", error);
        goto done;
    }
    do_unmount1 = 1;

    error = do_mount_URL(mp2, urlRef1, NULL, MNT_DONTBROWSE);
    if (error != 0) {
        XCTFail("TEST 3, mntFlags = MNT_DONTBROWSE: Second volume return wrong error: %d\n", error);
        goto done;
    }
    do_unmount2 = 1;

    /* Try unmount of mp1 */
    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("TEST 3 unmount mp1 failed %d\n", errno);
        goto done;
    }
    do_unmount1 = 0;

    /* Try unmount of mp2 */
    if (unmount(mp2, MNT_FORCE) == -1) {
        XCTFail("TEST 3 unmount mp2 failed %d\n", errno);
        goto done;
    }
    do_unmount2 = 0;

    
    /* Test four: mount first browse second browse */
    printf("Test 4: mount first with browse then second mount with browse which should get EEXIST \n");

    error = do_mount_URL(mp1, urlRef1, NULL, 0);
    if (error) {
        XCTFail("TEST 4, mntFlags = 0: Couldn't mount first volume: shouldn't happen %d\n", error);
        goto done;
    }
    do_unmount1 = 1;

    error = do_mount_URL(mp2, urlRef1, NULL, 0);
    if (error != EEXIST) {
        XCTFail("TEST 4, mntFlags = 0: Second volume return wrong error: %d\n", error);
        
        /* If second mount somehow succeeded, try to unmount it now. */
        if ((error == 0) && (unmount(mp2, MNT_FORCE) == -1)) {
            XCTFail("TEST 4 unmount mp2 failed %d\n", errno);
            /* try force unmount on exit */
            do_unmount2 = 1;
        }
        goto done;
    }

    /* Try unmount of mp1 */
    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("TEST 4 unmount mp1 failed %d\n", errno);
        goto done;
    }
    do_unmount1 = 0;


    /* Test five: mount first automount second no flags */
    printf("Test 5: mount first with automount then second mount with browse \n");

    error = do_mount_URL(mp1, urlRef1, NULL, MNT_AUTOMOUNTED);
    if (error) {
        XCTFail("TEST 5, mntFlags = MNT_AUTOMOUNTED: Couldn't mount first volume: shouldn't happen %d\n", error);
        goto done;
    }
    do_unmount1 = 1;

    error = do_mount_URL(mp2, urlRef1, NULL, 0);
    if (error != 0) {
        XCTFail("TEST 5, mntFlags = 0: Second volume return wrong error: %d\n", error);
        goto done;
    }
    do_unmount2 = 1;

    /* Try unmount of mp1 */
    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("TEST 5 unmount mp1 failed %d\n", errno);
        goto done;
    }
    do_unmount1 = 0;

    /* Try unmount of mp2 */
    if (unmount(mp2, MNT_FORCE) == -1) {
        XCTFail("TEST 5 unmount mp2 failed %d\n", errno);
        goto done;
    }
    do_unmount2 = 0;


    /* Test six: mount first no flags second automount */
    printf("Test 6: mount first with browse then second mount with automount \n");

    error = do_mount_URL(mp1, urlRef1, NULL, 0);
    if (error) {
        XCTFail("TEST 6, mntFlags = 0: Couldn't mount first volume: shouldn't happen %d\n", error);
        goto done;
    }
    do_unmount1 = 1;

    error = do_mount_URL(mp2, urlRef1, NULL, MNT_AUTOMOUNTED);
    if (error != 0) {
        XCTFail("TEST 6, mntFlags = MNT_AUTOMOUNTED: Second volume return wrong error: %d\n", error);
        goto done;
    }
    do_unmount2 = 1;

    /* Try unmount of mp1 */
    if (unmount(mp1, MNT_FORCE) == -1) {
        XCTFail("TEST 5 unmount mp1 failed %d\n", errno);
        goto done;
    }
    do_unmount1 = 0;

    /* Try unmount of mp2 */
    if (unmount(mp2, MNT_FORCE) == -1) {
        XCTFail("TEST 5 unmount mp2 failed %d\n", errno);
        goto done;
    }
    do_unmount2 = 0;

    printf("All mount exists tests pass \n");
    
done:
    if (do_unmount1) {
        if (unmount(mp1, MNT_FORCE) == -1) {
            XCTFail("unmount failed for first url %d\n", errno);
        }
    }

    if (do_unmount2) {
        if (unmount(mp2, MNT_FORCE) == -1) {
            XCTFail("unmount failed for second url %d\n", errno);
        }
    }

    rmdir(mp1);
    rmdir(mp2);

    return;
}

-(void)testNetBIOSNameConversion
{
    static const struct {
        CFStringRef    proposed;
        CFStringRef    expected;
    } test_names[] = {
        { NULL , NULL },
        { CFSTR(""), NULL },
        { CFSTR("james"), CFSTR("JAMES") },
        { CFSTR("colley-xp4"), CFSTR("COLLEY-XP4") },
        //{ CFSTR("jåmes"), CFSTR("JAMES") }, /* Unknown failure */
        //{ CFSTR("iPadæøåýÐ만돌"), CFSTR("IPADAYMANDOL") }, /* Unknown failure */
        { CFSTR("longnameshouldbetruncated"), CFSTR("LONGNAMESHOULDB") }
    };

    unsigned ii;
    unsigned count = (unsigned)(sizeof(test_names) / sizeof(test_names[0]));

    for (ii = 0; ii < sizeof(test_names) / sizeof(test_names[0]); ++ii) {
        CFStringRef converted;

        converted = SMBCreateNetBIOSName(test_names[ii].proposed);
        if (converted == NULL && test_names[ii].expected == NULL) {
            /* Expected this to fail ... good! */
            --count;
            continue;
        }

        if (!converted) {
            char buf[256];

            buf[0] = '\0';
            CFStringGetCString(test_names[ii].proposed, buf, sizeof(buf), kCFStringEncodingUTF8);

            XCTFail("failed to convert '%s'\n", buf);
            continue;
        }

        // CFShow(converted);

        if (CFEqual(converted, test_names[ii].expected)) {
            /* pass */
            --count;
        }
        else {
            char buf1[256];
            char buf2[256];

            buf1[0] = buf2[0] = '\0';
            CFStringGetCString(test_names[ii].expected, buf1, sizeof(buf1), kCFStringEncodingUTF8);
            CFStringGetCString(converted, buf2, sizeof(buf2), kCFStringEncodingUTF8);

            XCTFail("expected '%s' but received '%s'\n", buf1, buf2);
        }

        CFRelease(converted);
    }
    
    if (count == 0) {
        printf("All netbios names converted successfully \n");
    }
    
#if 0
    /*
     * %%% TO DO - SOMEDAY %%%
     * rdar://78620392 (Unit test of testNetBIOSNameConversion is failing for two odd names)
     * Debugging code to try to figure out why CFSTR("jåmes") and
     * CFSTR("iPadæøåýÐ만돌").
     *
     * This code is copied from SMBCreateNetBIOSName()
     *
     * Could not figure it out, something to do with
     * the code page translations, I think.
     */
    {
        /* This is the code page for 437, cp437 and should be the right one */
        CFStringEncoding codepage = kCFStringEncodingDOSLatinUS;
        CFMutableStringRef composedName;
        CFIndex nconverted = 0;
        uint8_t name_buffer[NetBIOS_NAME_LEN];
        CFIndex nused = 0;

        composedName = CFStringCreateMutableCopy(kCFAllocatorDefault, 0,
                                                 CFSTR("jåmes"));
        CFShow(composedName);
        
        CFStringUppercase(composedName, CFLocaleGetSystem());
        CFShow(composedName);
        
        printf("codepage %d \n", codepage);

        nconverted = CFStringGetBytes(composedName,
                                      CFRangeMake(0, MIN((CFIndex) sizeof(name_buffer), CFStringGetLength(composedName))),
                                      codepage, 0 /* loss byte */, false /* no BOM */,
                                      name_buffer, sizeof(name_buffer), &nused);

        /*
         * At this point, we are supposed to have CFSTR("JAMES"), but instead
         * we end up with "J\u00c5MES".
         */

        if (nconverted == 0) {
            char buf[256];

            buf[0] = '\0';
            CFStringGetCString(composedName, buf, sizeof(buf), kCFStringEncodingUTF8);
            printf("failed to compose a NetBIOS name string from '%s'", buf);
        }
        else {
            printf("nconverted %ld \n", (long) nconverted);
            CFShow(composedName);
        }

        CFRelease(composedName);

    }
#endif
}



@end
