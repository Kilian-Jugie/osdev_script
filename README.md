# osdev.sh
Operating system development environment setup script

Capabilities:
 - Multiple and extendable targets for single tools workspace
 - Multiple and extendable linux distribution support
 - GCC/binutils cross compiler compilatioon
 - QEMU compilation

# How to use
A target refers to the architecture of the development target. Cross-GCC will be built to produce executables for this architecture.
  
## First launch
1. Put osdev.sh in a developement folder (empty not required but advised)
2. Start osdev.sh without arguments (bash support required)
3. Follow [New project](#markdown-header-new-project)

## New project
1. Launch osdev.sh
2. Enter the project name, a new folder will be created for it (aka "DEV_DIR")
3. osdev will detect new project and directly start the [target creation](#markdown-header-new-target) procedure
4. 
5. 

## New target
1. Select the target architecture
2. Depending on installed packages

## Launch
1. Start osdev.sh
2. 

# Contribution
## Adding support for OS
## Adding target architecture

## TODO
 - Aliases for targets (x64 instead of x86_64-elf)
 - Error managment of build phases (stop script on error)
 - QEMU as target-independant
 - osdev.sh arguments for automating