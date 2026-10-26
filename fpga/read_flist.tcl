
# Read a Verilog file list into the current Vivado project.
#
# Supported entries:
#   /path/to/file.v
#   +incdir+/path/to/include
#
# Usage:
#   read_flist "/path/to/files.f"

proc read_flist {flist} {

    if {![file exists $flist]} {
        error "File list does not exist: $flist"
    }

    set flist [file normalize $flist]
    set fp [open $flist r]

    set files_added 0
    set incdirs_added 0

    # Get the current source fileset.
    set fileset [current_fileset -srcset]

    while {[gets $fp line] >= 0} {

        # Remove leading/trailing whitespace.
        set line [string trim $line]

        # Ignore blank lines and comments.
        if {$line eq "" || [string match "#*" $line]} {
            continue
        }

        # Handle +incdir+ directives.
        if {[string match "+incdir+*" $line]} {

            set incdir [string range $line 8 end]
            set incdir [string trim $incdir]

            if {$incdir eq ""} {
                puts "WARNING: Empty incdir directive in $flist"
                continue
            }

            if {![file isdirectory $incdir]} {
                puts "WARNING: Include directory does not exist: $incdir"
                continue
            }

            set incdir [file normalize $incdir]

            # Add to the Verilog include search path.
            set_property include_dirs \
                [concat [get_property include_dirs $fileset] [list $incdir]] \
                $fileset

            incr incdirs_added
            puts "INCDir: $incdir"

        } else {

            # Resolve relative paths relative to the file-list directory.
            if {[file pathtype $line] ne "absolute"} {
                set line [file join [file dirname $flist] $line]
            }

            if {![file exists $line]} {
                puts "WARNING: RTL file does not exist: $line"
                continue
            }

            set line [file normalize $line]

            # Add Verilog/SystemVerilog source.
            set ext [string tolower [file extension $line]]

            switch -- $ext {
                ".v" {
                    read_verilog $line
                }
                ".sv" {
                    read_verilog -sv $line
                }
                default {
                    puts "WARNING: Unsupported source file type: $line"
                    continue
                }
            }

            incr files_added
            puts "RTL: $line"
        }
    }

    close $fp

    puts "----------------------------------------"
    puts "File list processed: $flist"
    puts "RTL files added:     $files_added"
    puts "Include directories: $incdirs_added"
    puts "----------------------------------------"
}
