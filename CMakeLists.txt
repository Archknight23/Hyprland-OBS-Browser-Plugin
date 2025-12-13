cmake_minimum_required(VERSION 3.16)
project(hyprland-browser-wrapper VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(GNUInstallDirs)

# Find OBS and Qt6 packages
# WebEngineWidgets is required for the browser view
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBOBS REQUIRED libobs)
find_package(Qt6 COMPONENTS Widgets Core Gui WebEngineWidgets REQUIRED)

# Define the plugin library
add_library(hyprland-browser-wrapper MODULE
    src/plugin_main.cpp
)

# Make sure obs headers are visible (libobs installs to /usr/include/obs on many distros)
target_include_directories(hyprland-browser-wrapper PRIVATE
    ${LIBOBS_INCLUDE_DIRS}
    /usr/include/obs
)

# Link necessary libraries
target_link_libraries(hyprland-browser-wrapper
    PRIVATE
    PkgConfig::LIBOBS
    Qt6::Core
    Qt6::Widgets
    Qt6::Gui
    Qt6::WebEngineWidgets
)

# Installation paths
if(NOT DEFINED OBS_PLUGIN_DESTINATION)
    set(OBS_PLUGIN_DESTINATION "${CMAKE_INSTALL_LIBDIR}/obs-plugins")
endif()

if(NOT DEFINED OBS_DATA_DESTINATION)
    set(OBS_DATA_DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/obs/obs-plugins/hyprland-browser-wrapper")
endif()

install(TARGETS hyprland-browser-wrapper DESTINATION "${OBS_PLUGIN_DESTINATION}")
