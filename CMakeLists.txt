#
# Copyright (c) 2024 Nordic Semiconductor ASA
#
# SPDX-License-Identifier: LicenseRef-Nordic-5-Clause
#

cmake_minimum_required(VERSION 3.20.0)

# snippets.cmake runs before zephyr/ exists; snippets.py mkdir() lacks parents=True (WinError 3).
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/zephyr")

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(ble_hrs_central)

target_sources(app PRIVATE src/main.c)

# --- Post-build: show App + SoftDevice flash size summary ---
if(NOT SD_HEX)
	set(SD_HEX "E:/ncs/nrf-bm/v1.0.0/nrf-bm/components/softdevice/s145/s145_nrf54l15_9.0.0_softdevice.hex")
endif()
set(APP_BIN "${CMAKE_BINARY_DIR}/zephyr/zephyr.bin")
set(TOTAL_FLASH_KB 1524)

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/flash_size_summary.py.in"
    "${CMAKE_BINARY_DIR}/flash_size_summary.py"
    @ONLY
)

add_custom_command(TARGET app POST_BUILD
    COMMAND ${PYTHON_EXECUTABLE} "${CMAKE_BINARY_DIR}/flash_size_summary.py"
    VERBATIM
)
