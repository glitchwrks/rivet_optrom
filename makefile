###############################################################################
# Makefile for building BIOS binary files.                                    #
# v. 1.0.0 (28.7.2007 ... 28.7.2007)                                          #
# (C) Tomi Tilli                                                              #
# aitotat@gmail.com                                                           #
#                                                                             #
# Modified 2026 by Glitch Works, LLC: builds natively with GNU make and NASM  #
# on Unix-like systems, and sets the option ROM checksum byte.                #
#                                                                             #
# Valid makefile targets are:                                                 #
# all       Removes existing files and builds all binary files in Build/      #
# build     Builds all binary files in Build/                                 #
# at        AT build (286+)                                                   #
# xtplus    XT+ build (80186/80188, V20/V30)                                  #
# xt        XT build (8086/8088)                                              #
# check     Builds, then checks images against Tools/baseline.sha256          #
# clean     Removes Build/                                                    #
#                                                                             #
# Override the assembler or Python interpreter on the command line, e.g.:     #
#   make AS=yasm                                                              #
#   make PYTHON=python3.11                                                    #
###############################################################################

###########################################
# Source files and destination executable #
###########################################

# Assembly source code file (*.asm):
SRC_ASM = Src/Main.asm

# Program executable file name without extension:
PROG = rivet


#######################################
# Destination and include directories #
#######################################

# Directory where binary files will be built
BUILD_DIR = Build

# Subdirectories where included files are:
HEADERS = Inc/
HEADERS += Src/
HEADERS += Src/Boot/
HEADERS += Src/Handlers/
HEADERS += Src/Handlers/Int13h/
HEADERS += Src/Handlers/Int13h/Common/
HEADERS += Src/Initialization/
HEADERS += Src/Libraries/
HEADERS += Src/Libraries/menu/
HEADERS += Src/VariablesAndDPTs/


#################################################################
# Assembler preprocessor defines.                               #
#################################################################
DEFINES =
DEFINES_XT =
DEFINES_XTPLUS = USE_186
DEFINES_AT = USE_186 USE_286 USE_AT


###################
# Other variables #
###################

# Add -D in front of every preprocessor define declaration
DEFS = $(DEFINES:%=-D%)
DEFS_XT = $(DEFINES_XT:%=-D%)
DEFS_XTPLUS = $(DEFINES_XTPLUS:%=-D%)
DEFS_AT = $(DEFINES_AT:%=-D%)

# Add -I in front of all header directories
IHEADERS = $(HEADERS:%=-I%)

# Path + target file to be built
TARGET = $(BUILD_DIR)/$(PROG)

# All source and include files, so binaries rebuild when anything changes
DEPS = $(shell find Src Inc -name '*.asm' -o -name '*.inc')


##########################
# Tools                  #
##########################

# Assembler
AS = nasm

# Python 3 interpreter, used for the checksum tool
PYTHON = python3

# Option ROM checksum tool
CHECKSUM = $(PYTHON) Tools/checksum.py


#############################
# Assembler flags           #
#############################

# -f bin            Produce binary object files
# $(DEFS)           Preprocessor defines
# $(IHEADERS)       Set header file directory paths
# -Worphan-labels   Warn about labels without colon
# -O9               Optimize operands to their shortest forms
ASFLAGS = -f bin $(DEFS) $(IHEADERS) -Worphan-labels -O9


############################################
# Build process. Actual work is done here. #
############################################

.PHONY: all build at xtplus xt check clean

all: clean build
	@echo All built!

build: at xtplus xt

at: $(TARGET)_at.bin
xtplus: $(TARGET)_xtp.bin
xt: $(TARGET)_xt.bin

$(BUILD_DIR):
	mkdir -p $@

$(TARGET)_at.bin: $(DEPS) Tools/checksum.py | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(DEFS_AT) -o $@ $(SRC_ASM)
	$(CHECKSUM) $@

$(TARGET)_xtp.bin: $(DEPS) Tools/checksum.py | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(DEFS_XTPLUS) -o $@ $(SRC_ASM)
	$(CHECKSUM) $@

$(TARGET)_xt.bin: $(DEPS) Tools/checksum.py | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(DEFS_XT) -o $@ $(SRC_ASM)
	$(CHECKSUM) $@

check: build
	$(PYTHON) Tools/check_baseline.py -v Tools/baseline.sha256

clean:
	rm -rf $(BUILD_DIR)
