cmake_minimum_required(VERSION 3.17)

set(CMAKE_DISABLE_SOURCE_CHANGES ON)
set(CMAKE_DISABLE_IN_SOURCE_BUILD ON)

# Ensure to pick up the default triplet from the environment if any. This helps
# driving the vcpkg triplet in the same way either when starting vcpkg directly,
# or when letting CMake start vcpkg at configure/generate time.
# Note: this logic must happen before PROJECT command.
if (DEFINED ENV{VCPKG_DEFAULT_TRIPLET} AND NOT DEFINED VCPKG_TARGET_TRIPLET)
    set(VCPKG_TARGET_TRIPLET "$ENV{VCPKG_DEFAULT_TRIPLET}" CACHE STRING "The vcpkg triplet")
endif()

option(BUILD_TESTING "Build unit tests" OFF)
if (BUILD_TESTING)
    list(APPEND VCPKG_MANIFEST_FEATURES "unit-tests")
endif()

project(tfs CXX)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

if (NOT WIN32)
    add_compile_options(-Wall -Wextra -Wnon-virtual-dtor -Wold-style-cast -pedantic -Werror -pipe -fvisibility=hidden)
endif ()

if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
    add_compile_options(-fno-strict-aliasing)
endif ()

if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
    add_compile_options(-Wimplicit-fallthrough -Wmove)
endif ()

# Find packages.
find_package(OpenSSL 3.0.0 REQUIRED COMPONENTS Crypto)

find_package(fmt CONFIG)
if (NOT fmt_FOUND)
    find_package(fmt 6.1.2 REQUIRED)
endif()

# Look for vcpkg-provided libmariadb first
# If we link to the file directly, we might miss its dependencies from vcpkg
find_package(unofficial-libmariadb CONFIG)
if (unofficial-libmariadb_FOUND)
    set(MYSQL_CLIENT_LIBS "unofficial::libmariadb")
else ()
    find_package(MySQL REQUIRED)
endif ()

find_package(Threads REQUIRED)
find_package(PugiXML CONFIG REQUIRED)

# Selects LuaJIT if user defines or auto-detected
if (DEFINED USE_LUAJIT AND NOT USE_LUAJIT)
    set(FORCE_LUAJIT ${USE_LUAJIT})
else ()
    find_package(LuaJIT)
    set(FORCE_LUAJIT ${LuaJIT_FOUND})
endif ()
option(USE_LUAJIT "Use LuaJIT" ${FORCE_LUAJIT})

if (NOT FORCE_LUAJIT)
    find_package(Lua REQUIRED)
endif ()

if (APPLE)
    find_package(Iconv REQUIRED)
endif()

set(BOOST_REQUIRED_COMPONENTS system iostreams locale)
if (BUILD_TESTING)
    list(APPEND BOOST_REQUIRED_COMPONENTS unit_test_framework)
endif ()
find_package(Boost 1.66.0 REQUIRED COMPONENTS ${BOOST_REQUIRED_COMPONENTS})

include_directories(${Boost_INCLUDE_DIRS} ${OPENSSL_INCLUDE_DIR} ${LUA_INCLUDE_DIR} ${MYSQL_INCLUDE_DIR} ${PUGIXML_INCLUDE_DIR})

# Option to disable OTS Stats
option(ENABLE_OTS_STATISTICS "OTS Statistics" ON)
if (ENABLE_OTS_STATISTICS)
    message(STATUS "OTS Statistics enabled")
    add_definitions(-DSTATS_ENABLED)
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_subdirectory(src)
add_executable(tfs ${tfs_MAIN})
target_link_libraries(tfs tfslib)

target_link_options(tfs PUBLIC -flto=auto)

if (BUILD_TESTING)
    message(STATUS "Building unit tests")
    enable_testing()
    add_subdirectory(src/tests)
endif()

### INTERPROCEDURAL_OPTIMIZATION ###
cmake_policy(SET CMP0069 NEW)
include(CheckIPOSupported)
check_ipo_supported(RESULT result OUTPUT error)
if (result)
    message(STATUS "IPO / LTO enabled")
    set_target_properties(tfs PROPERTIES INTERPROCEDURAL_OPTIMIZATION True)
else ()
    message(STATUS "IPO / LTO not supported: <${error}>")
endif ()
### END INTERPROCEDURAL_OPTIMIZATION ###

### Git Version ###
# Define the two required variables before including
# the source code for watching a git repository.
option(SKIP_GIT "Skip checking for git updates" OFF)
if(NOT SKIP_GIT)
    set(PRE_CONFIGURE_FILE "cmake/gitmetadata.h.in")
    set(POST_CONFIGURE_FILE "${CMAKE_CURRENT_BINARY_DIR}/gitmetadata.h")
    include(git_watcher)
    if(Git_FOUND)
        add_dependencies(tfs check_git)
        target_include_directories(tfs PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
    endif()
endif()
### END  Git Version ###

# Option to disable unity builds
option(ENABLE_UNITY_BUILD "Enable unity build" ON)
if(ENABLE_UNITY_BUILD)
    set_target_properties(tfslib PROPERTIES UNITY_BUILD ON)
endif()

target_precompile_headers(tfs PUBLIC src/otpch.h)
