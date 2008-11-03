@echo off
REM ======================================================================
REM First set all the variables that contain common bits for our build
REM environment.
REM * * * * * * * * * * * * * PLEASE READ* * * * * * * * * * * * * * * *
REM Microsoft Visual Studio will choke on variables that contain strings 
REM exceeding 255 chars, so be careful when editing this file! It's 
REM totally lame but there's nothing we can do about it.
REM ======================================================================

rem We assume all software is installed on the main system drive, but
rem in the case that it is not, change the variable bellow.
set ROOT_DRIVE=%SystemDrive%

REM Set paths to Visual C++, the Platform SDKs, and Perl
set VC_DIR=%ROOT_DRIVE%\Program Files\Microsoft Visual Studio\VC98\Bin
set SDK_DIR=%ROOT_DRIVE%\Program Files\Microsoft Platform SDK
set PERL_DIR=%ROOT_DRIVE%\Perl\bin
set DBG_DIR=%ROOT_DRIVE%\Program Files\Debugging Tools for Windows

rem Specify symbol image path
if A%_NT_SYMBOL_PATH%==A set _NT_SYMBOL_PATH=SRV*%ROOT_DRIVE%\Symbols*http://msdl.microsoft.com/download/symbols

REM Where do the completed externals live?
if A%EXTERN_DIR%==A  set EXTERN_DIR=%cd%\..\externals
set EXT_INSTALL=%EXTERN_DIR%\install
set EXT_TRIGGERS=%EXTERN_DIR%\triggers

REM Specify which versions of the externals we're using. To add a 
REM new external, just add its version here, and add that to the 
REM EXTERNALS_NEEDED variable defined below.
set EXT_GSOAP_VERSION=gsoap-2.7.6c-p2
set EXT_OPENSSL_VERSION=openssl-0.9.8
set EXT_POSTGRESQL_VERSION=postgresql-8.0.2
set EXT_KERBEROS_VERSION=krb5-1.4.3
set EXT_GLOBUS_VERSION=
set EXT_PCRE_VERSION=pcre-7.6
set EXT_DRMAA_VERSION=drmaa-1.5.1

REM Now tell the build system what externals we need built.
set EXTERNALS_NEEDED=%EXT_GSOAP_VERSION% %EXT_OPENSSL_VERSION% %EXT_KERBEROS_VERSION% %EXT_GLOBUS_VERSION% %EXT_PCRE_VERSION% %EXT_POSTGRESQL_VERSION% %EXT_DRMAA_VERSION%

REM Put NTConfig in the PATH, since it's got lots of stuff we need
REM like awk, gunzip, tar, bison, yacc...
set PATH=%cd%;%SystemRoot%;%SystemRoot%\system32;%PERL_DIR%;%VC_DIR%;%SDK_DIR%;%DBG_DIR%

REM ======================================================================
REM ====== THIS SHOULD BE REMOVED WHEN Win2K IS NO LONGER SUPPORTED ======
REM Since we a still stuck in the past (i.e. supporting Win2K) we must
REM lie to the setenv script, and pretend the DevEnvDir environment
REM is alredy configured properly (yay! jump to VC2K8, but support
REM Win2K... *sigh*) 
set MSVCDir=%VC_DIR%
set DevEnvDir=C:\Program Files\Microsoft Visual Studio\COMMON\MSDev98\Bin
SET MSVCVer=6.0
REM ====== THIS SHOULD BE REMOVED WHEN Win2K IS NO LONGER SUPPORTED ======
REM ======================================================================

call vcvars32.bat
if not defined INCLUDE ( echo . && echo *** Failed to run VCVARS32.BAT! Is Microsoft Visual Studio 6.0 installed? && exit /B 1 )
call setenv /2000 /RETAIL
if not defined MSSDK ( echo . && echo *** Failed to run SETENV.BAT! Is Microsoft Platform SDK installed? && exit /B 1 )

REM Set up some stuff for BISON
set BISON_SIMPLE=%cd%\bison.simple
set BISON_HAIRY=%cd%\bison.hairy

REM Tell the build system where we can find soapcpp2
set SOAPCPP2=%EXT_INSTALL%\%EXT_GSOAP_VERSION%\soapcpp2.exe

REM Determine the build id, if it is defined
pushd ..
set BID=none
if exist BUILD-ID. (
    echo Found BUILD-ID in %cd%
    for /f %%i in ('more BUILD-ID') do set BID=%%i
) else (
    echo No build-id defined: the file %cd%\BUILD-ID is missing.
)
echo Using build-id: %BID% & echo.
popd

set CONDOR_INCLUDE=/I "..\src\h" /I "..\src\condor_includes" /I "..\src\condor_c++_util" /I "..\src\condor_daemon_client" /I "..\src\condor_daemon_core.V6" /I "..\src\condor_schedd.V6" /GR /DHAVE_HIBERNATION=0 /DHAVE_JOB_HOOKS /DBUILDID=%BID%
set CONDOR_LIB=Crypt32.lib mpr.lib psapi.lib mswsock.lib netapi32.lib imagehlp.lib advapi32.lib ws2_32.lib user32.lib oleaut32.lib ole32.lib powrprof.lib iphlpapi.lib userenv.lib
set CONDOR_LIBPATH=

REM Tell VC makefiles that we do not wish to use external dependency
REM (.dep) files.
set NO_EXTERNAL_DEPS=1

REM ======================================================================
REM Now set the individual variables specific to each external package.
REM Some have been defined, but are not in use yet.
REM ======================================================================

REM ** GSOAP
set CONDOR_GSOAP_INCLUDE=/I %EXT_INSTALL%\%EXT_GSOAP_VERSION%\src /DHAVE_BACKFILL=1 /DHAVE_BOINC=1 /DWITH_OPENSSL=1 /DCOMPILE_SOAP_SSL=1 /DHAVE_EXT_GSOAP=1
set CONDOR_GSOAP_LIB=
set CONDOR_GSOAP_LIBPATH=

REM ** GLOBUS
set CONDOR_GLOBUS_INCLUDE=
set CONDOR_GLOBUS_LIB=
set CONDOR_GLOBUS_LIBPATH=

REM ** OPENSSL
set CONDOR_OPENSSL_INCLUDE=/I %EXT_INSTALL%\%EXT_OPENSSL_VERSION%\inc32 /D HAVE_EXT_OPENSSL
set CONDOR_OPENSSL_LIB=libeay32.lib ssleay32.lib
set CONDOR_OPENSSL_LIBPATH=/LIBPATH:%EXT_INSTALL%\%EXT_OPENSSL_VERSION%\out32dll
rem set CONDOR_OPENSSL_LIBPATH=/LIBPATH:%EXT_INSTALL%\%EXT_OPENSSL_VERSION%\out32dll /NODEFAULTLIB:LIBCMT.LIB

REM ** POSTGRESQL
set CONDOR_POSTGRESQL_INCLUDE=/I %EXT_INSTALL%\%EXT_POSTGRESQL_VERSION%\inc32 /D WANT_QUILL
set CONDOR_POSTGRESQL_LIB=libpqdll.lib
set CONDOR_POSTGRESQL_LIBPATH=/LIBPATH:%EXT_INSTALL%\%EXT_POSTGRESQL_VERSION%\out32dll

REM ** KERBEROS
set CONDOR_KERB_INCLUDE=/I %EXT_INSTALL%\%EXT_KERBEROS_VERSION%\include /D HAVE_EXT_KRB5
set CONDOR_KERB_LIB=comerr32.lib gssapi32.lib k5sprt32.lib krb5_32.lib xpprof32.lib
set CONDOR_KERB_LIBPATH=/LIBPATH:%EXT_INSTALL%\%EXT_KERBEROS_VERSION%\lib

REM ** PCRE
set CONDOR_PCRE_INCLUDE=/I %EXT_INSTALL%\%EXT_PCRE_VERSION%\include
set CONDOR_PCRE_LIB=libpcre.lib
set CONDOR_PCRE_LIBPATH=/LIBPATH:%EXT_INSTALL%\%EXT_PCRE_VERSION%\lib

exit /B 0

