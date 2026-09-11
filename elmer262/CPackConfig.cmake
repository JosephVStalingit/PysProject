# This file will be configured to contain variables for CPack. These variables
# should be set in the CMake list file of the project before CPack module is
# included. The list of available CPACK_xxx variables and their associated
# documentation may be obtained using
#  cpack --help-variable-list
#
# Some variables are common to all generators (e.g. CPACK_PACKAGE_NAME)
# and some are specific to a generator
# (e.g. CPACK_NSIS_EXTRA_INSTALL_COMMANDS). The generator specific variables
# usually begin with CPACK_<GENNAME>_xxxx.


set(CPACK_ARCHIVE_GID "-1")
set(CPACK_ARCHIVE_UID "-1")
set(CPACK_BUILD_SOURCE_DIRS "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1;C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/build")
set(CPACK_BUNDLE_EXTRA_WINDOWS_DLLS "TRUE")
set(CPACK_CMAKE_GENERATOR "Ninja")
set(CPACK_COMPONENT_ELMERGUI_DISPLAY_NAME "ElmerGUI")
set(CPACK_COMPONENT_ELMERGUI_SAMPLES_DESCRIPTION "Geometry samples for ElmerGUI")
set(CPACK_COMPONENT_ELMERGUI_SAMPLES_DISPLAY_NAME "ElmerGUI samples")
set(CPACK_COMPONENT_ELMERPOST_DESCRIPTION "A post processor for Elmer")
set(CPACK_COMPONENT_ELMERPOST_DISPLAY_NAME "ElmerPost")
set(CPACK_COMPONENT_INSTALL_ALL "elmergui gfortran_minimal Unspecified elmergui_samples ElmerPost")
set(CPACK_COMPONENT_UNSPECIFIED_DESCRIPTION "The main application: ElmerSolver, ElmerGrid, matc and runtime binaries.")
set(CPACK_COMPONENT_UNSPECIFIED_DISPLAY_NAME "Elmerfem solver")
set(CPACK_COMPONENT_UNSPECIFIED_HIDDEN "TRUE")
set(CPACK_COMPONENT_UNSPECIFIED_REQUIRED "TRUE")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "libblas-dev, liblapack-dev")
set(CPACK_DEFAULT_PACKAGE_DESCRIPTION_FILE "C:/msys64/mingw64/share/cmake/Templates/CPack.GenericDescription.txt")
set(CPACK_DEFAULT_PACKAGE_DESCRIPTION_SUMMARY "Elmer built using CMake")
set(CPACK_DMG_SLA_USE_RESOURCE_FILE_LICENSE "ON")
set(CPACK_GENERATOR "NSIS;ZIP")
set(CPACK_INNOSETUP_ARCHITECTURE "x64")
set(CPACK_INSTALL_CMAKE_PROJECTS "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/build;Elmer;ALL;/")
set(CPACK_INSTALL_PREFIX "C:/Program Files/Elmer 26.2.1-Release")
set(CPACK_MODULE_PATH "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/cmake/Modules;C:/msys64/mingw64/share/cmake/Modules")
set(CPACK_NSIS_COMPONENT_INSTALL "TRUE")
set(CPACK_NSIS_CONTACT "")
set(CPACK_NSIS_DISPLAY_NAME " Elmer")
set(CPACK_NSIS_DISPLAY_NAME_SET "TRUE")
set(CPACK_NSIS_EXTRA_INSTALL_COMMANDS "   !include \"winmessages.nsh\"
   ; HKLM (all users) vs HKCU (current user) defines
   !define env_hklm 'HKLM \"SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment\"'
   !define env_hkcu 'HKCU \"Environment\"'
   StrCmp \$ADD_TO_PATH_ALL_USERS \"1\" WriteAllElmerHomeKey
     DetailPrint \"Selected environment for current user\"
     WriteRegExpandStr \${env_hkcu} ELMER_HOME \$INSTDIR
     WriteRegExpandStr \${env_hkcu} ELMERGUI_HOME \$INSTDIR\\share\\ElmerGUI
     Goto DoSendElmerHome
   WriteAllElmerHomeKey:
     DetailPrint \"Selected environment for all users\"
     WriteRegExpandStr \${env_hklm} ELMER_HOME \$INSTDIR
     WriteRegExpandStr \${env_hklm} ELMERGUI_HOME \$INSTDIR\\share\\ElmerGUI 
     DoSendElmerHome:
   SendMessage \${HWND_BROADCAST} \${WM_WININICHANGE} 0 \"STR:Environment\" /TIMEOUT=5000 ")
set(CPACK_NSIS_EXTRA_UNINSTALL_COMMANDS "   ; delete variable
   StrCmp \${ADD_TO_PATH_ALL_USERS} \"1\" unWriteAllElmerHome
     DeleteRegValue \${env_hkcu} ELMER_HOME 
     DeleteRegValue \${env_hkcu} ELMERGUI_HOME 
     Goto unDoSendElmerHome
   unWriteAllElmerHome:
     DeleteRegValue \${env_hklm} ELMER_HOME
     DeleteRegValue \${env_hklm} ELMERGUI_HOME
   unDoSendElmerHome:
     SendMessage \${HWND_BROADCAST} \${WM_WININICHANGE} 0 \"STR:Environment\" /TIMEOUT=5000")
set(CPACK_NSIS_HELP_LINK "http://www.elmerfem.org")
set(CPACK_NSIS_INSTALLER_ICON_CODE "")
set(CPACK_NSIS_INSTALLER_MUI_ICON_CODE "")
set(CPACK_NSIS_INSTALL_ROOT "$PROGRAMFILES64")
set(CPACK_NSIS_MODIFY_PATH "ON")
set(CPACK_NSIS_PACKAGE_NAME " Elmer")
set(CPACK_NSIS_UNINSTALL_NAME "Uninstall")
set(CPACK_OBJCOPY_EXECUTABLE "C:/msys64/mingw64/bin/objcopy.exe")
set(CPACK_OBJDUMP_EXECUTABLE "C:/msys64/mingw64/bin/objdump.exe")
set(CPACK_OUTPUT_CONFIG_FILE "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/build/CPackConfig.cmake")
set(CPACK_PACKAGE_BASE_FILE_NAME "elmerfem")
set(CPACK_PACKAGE_CONTACT "elmeradm@csc.fi")
set(CPACK_PACKAGE_DEFAULT_LOCATION "/")
set(CPACK_PACKAGE_DESCRIPTION "Elmer is an open source multiphysical
simulation software mainly developed by CSC - IT Center for Science (CSC).
Elmer development was started 1995 in collaboration with Finnish
Universities, research institutes and industry. After it's open source
publication in 2005, the use and development of Elmer has become
international.

Elmer includes physical models of fluid dynamics, structural mechanics,
electromagnetics, heat transfer and acoustics, for example. These are
described by partial differential equations which Elmer solves by the Finite
Element Method (FEM).")
set(CPACK_PACKAGE_DESCRIPTION_FILE "C:/msys64/mingw64/share/cmake/Templates/CPack.GenericDescription.txt")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Open Source Finite Element Software for Multiphysical Problems")
set(CPACK_PACKAGE_FILE_NAME "elmerfem-26.2--20260910_Windows-AMD64")
set(CPACK_PACKAGE_INSTALL_DIRECTORY "Elmer 26.2-")
set(CPACK_PACKAGE_INSTALL_REGISTRY_KEY "Elmer 26.2-")
set(CPACK_PACKAGE_NAME "Elmer")
set(CPACK_PACKAGE_RELOCATABLE "true")
set(CPACK_PACKAGE_VENDOR "CSC")
set(CPACK_PACKAGE_VERSION "26.2-")
set(CPACK_PACKAGE_VERSION_MAJOR "26")
set(CPACK_PACKAGE_VERSION_MINOR "2")
set(CPACK_PACKAGE_VERSION_PATCH "")
set(CPACK_READELF_EXECUTABLE "C:/msys64/mingw64/bin/readelf.exe")
set(CPACK_RESOURCE_FILE_LICENSE "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/license_texts/LICENSES_GPL.txt")
set(CPACK_RESOURCE_FILE_README "C:/msys64/mingw64/share/cmake/Templates/CPack.GenericDescription.txt")
set(CPACK_RESOURCE_FILE_WELCOME "C:/msys64/mingw64/share/cmake/Templates/CPack.GenericWelcome.txt")
set(CPACK_SET_DESTDIR "OFF")
set(CPACK_SOURCE_7Z "ON")
set(CPACK_SOURCE_GENERATOR "7Z;ZIP")
set(CPACK_SOURCE_OUTPUT_CONFIG_FILE "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/build/CPackSourceConfig.cmake")
set(CPACK_SOURCE_ZIP "ON")
set(CPACK_SYSTEM_NAME "win64")
set(CPACK_THREADS "1")
set(CPACK_TOPLEVEL_TAG "win64")
set(CPACK_WIX_SIZEOF_VOID_P "8")

if(NOT CPACK_PROPERTIES_FILE)
  set(CPACK_PROPERTIES_FILE "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/build/CPackProperties.cmake")
endif()

if(EXISTS ${CPACK_PROPERTIES_FILE})
  include(${CPACK_PROPERTIES_FILE})
endif()
