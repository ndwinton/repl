#!/usr/bin/perl
#
# Gather/Scatter editing
#
# https://github.com/ndwinton/repl
#
# Neil Winton (neil@winton.org.uk)
#
# Copyright (c) 1999, 2002, 2003, 2012 by Neil Winton. All rights reserved.
# 
# The author hereby grants permission to use, copy, modify, distribute,
# and license this software and its documentation for any purpose,
# provided that existing copyright notices are retained in all copies
# and that this notice is included verbatim in any distributions. No
# written agreement, licence, or royalty fee is required for any of the
# authorized uses.
# 
# IN NO EVENT SHALL THE AUTHOR BE LIABLE TO ANY PARTY FOR DIRECT,
# INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT OF
# THE USE OF THIS SOFTWARE, ITS DOCUMENTATION, OR ANY DERIVATIVES
# THEREOF, EVEN IF THE AUTHOR HAS BEEN ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
# 
# THE AUTHOR SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE, AND NON-INFRINGEMENT. THIS SOFTWARE IS PROVIDED ON
# AN "AS IS" BASIS, AND THE AUTHOR HAS NO OBLIGATION TO PROVIDE
# MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
# 
#

eval "exec /usr/bin/perl \"$0\" ${1+\"$@\"}"
    if $running_under_some_shell;

use Getopt::Std;

$main::VERSION = 'repl - Gather/Scatter editing - 20120712';
$Getopt::Std::STANDARD_HELP_VERSION = 1;

getopts("1d:filRr:s:v");

# Set the default delimiter (|) over-ride with -d if necessary

$Delim = "|";
$Delim = $opt_d if ($opt_d ne '');
die "$0: Delimiter must be a single character\n" unless (length($Delim) == 1);

# If -s is specified then search for the specified pattern in the specified
# files. Also, special-case -f and -l options trigger search mode.

if ($opt_s ne '' || $opt_l ne '' || $opt_f ne '') {
    Search($opt_s, @ARGV);
}

# If -r is specified then apply the edits from the specified file

elsif ($opt_r ne '') {
    Replace($opt_r);
}

# Must specify either a search or replace mode!

else {
    Usage();
}

exit(0);

# Search all files named in the @ARGV array. If the search expression is
# found output a line of the following form:
#
#   <filename>|<line number>|c|<text of the line>
#
# The delimiter character can be over-ridden with -d if necessary.
# If there is no new-line then the 'c' will be suffixed with a '$'.

sub Search
{
    my $expr = shift;
    local(*ARGV);
    @ARGV = @_;
    return if ($#ARGV < 0);
    
    my ($file, $iflag, $test, @test);
 
    $iflag = "i" if ($opt_i);

    push(@test, '/$expr/o' . $iflag) if ($expr ne '');
    push(@test, '$. == 1') if ($opt_f);
    push(@test, 'eof(ARGV)') if ($opt_l);
    $test = join(' || ', @test);

eval <<EOT;
    \$seen = 0;
    while (<>) {
        if (!\$seen && $test) {
            if (/\\n/) {
                \$eol = '';
                \$nl = "";
            }
            else {
                \$eol = '\$';
                \$nl = "\\n";
            }
            print "\$ARGV${Delim}\$.${Delim}c\$eol${Delim}\$_\$nl";
            \$seen = '$opt_1';
        }
        if (eof(ARGV)) {
            \$. = 0;
            \$seen = 0;
        }
    }
EOT
    # If -R is specified then recurse into any directories specified
    # looking for (non-binary) files and search them too.

    RecurseDirs(@_) if ($opt_R);
}

# Replace (and otherwise edit) lines according to the instructions found in
# the specified edit file. Lines have the same general form as output by
# the search process, that is, they contain four fields delimited by "|"
# characters. The first field is the name of the file to be edited, the
# second is the line number to be acted on, the third is the "action" to
# be performed (explained below) and the last is the data for the line.
# The valid values for the action field are as follows:
#
#   c -- Change.
#        Replace the specified line with the line data
#
#   d -- Delete.
#        Delete the specified line (any line data is ignored)
#
#   i -- Insert.
#        Output the line data immediately before the specified line.
#        If more than one "i" action appears for a particular line then
#        the data are accumulated and inserted into the output in the
#        order in which they appear within the file.
#
#   a -- Append.
#        As for insert except that the data are output after the specified
#        line rather than before.
#
# The original file is backed up with a .bak extension prior to editing.
#
# If a delimiter was specified using -d at search time, the same delimiter
# must be secified during the replace operation.
#
# If the action field ends with '$' then no trailing new-line will be output.

sub Replace
{
    my ($editfile) = @_;
    my (%repInfo, $file, $num, $action, $eol, $line, $data);
    local (*IN, *OUT);


    die "$0: Can't open edit-file '$editfile' ($!)\n" unless open(IN, "<$editfile");
    while (<IN>) {
        # Match the edit control lines -- ignore others

        if (($file, $num, $action, $eol, $data) = /^([^\Q$Delim\E]+)\Q$Delim\E(\d+)\Q$Delim\E(.)(\$?)\Q$Delim\E(.*)/o) {
            push(@{$repInfo{$file}[$num]{$action}}, $data . ($eol eq '$' ? "" : "\n"));
        }
        else {
            print STDERR "$0: Bad edit line ($file, $num, $action, $data) -- ignored: $_"
        }
    }
    close(IN);

    foreach $file (sort(keys(%repInfo))) {
        print STDERR "Editing $file ...\n" if ($opt_v);

        if ($file ne "-") {
            die "$0: Can't read $file ($!)\n" unless (-r $file);
            die "$0: Can't rename $file to $file.bak ($!)\n" unless rename($file, "$file.bak");
            die "$0: Can't open $file.bak ($!)\n", unless open(IN, "<$file.bak");
        }
        die "$0: Can't create $file ($!)\n" unless open(OUT, ">$file");

        $num = 1;

        while (<IN>) {
            # Insert before current line

            if (defined($repInfo{$file}[$num]{i})) {
                foreach $line (@{$repInfo{$file}[$num]{i}}) {
                    print OUT $line;
                }
            }

            # Delete current line

            if (defined($repInfo{$file}[$num]{d})) {
                $_ = '';
            }

            # Change current line

            if (defined($repInfo{$file}[$num]{c})) {
                $_ = '';
                foreach $line (@{$repInfo{$file}[$num]{c}}) {
                    $_ .= $line;
                }
            }

            # Output current line

            print OUT $_;

            # Append after current line

            if (defined($repInfo{$file}[$num]{a})) {
                foreach $line (@{$repInfo{$file}[$num]{a}})
                {
                    print OUT $line;
                }
            }

            $num++;
        }

        close(IN);
        close(OUT);
    }
}

sub Usage
{
    HELP_MESSAGE(STDERR);
    exit 1;
}

# RecurseDirs
#
# Recursively search directories building a list of non-binary files

sub RecurseDirs
{
    my (@files, $entry, $path);
    local (*DIR);

    foreach (@_) {
        if (-d $_) {
            print STDERR "Searching $_ ...\n" if ($opt_v);
            next unless opendir(DIR, $_);
            foreach $entry (readdir(DIR)) {
                next if ($entry eq '.' || $entry eq '..');
                $path = $_ . "/" . $entry;
                push(@files, $path) if (-T $path || -d $path);
            }
            closedir(DIR);
        }
    }

    Search($opt_s, @files);
}

sub VERSION_MESSAGE {
    my $fh = shift;
    print $fh $main::VERSION;
}

sub HELP_MESSAGE {
    my $fh = shift;
    
    print $fh <<EOF;
Search:  $0 [-1iRv] [-d delim] [-f | -l | -s pattern] file ... > edit-file
Replace: $0 [-v] [-d delim] -r edit-file

This tool performs 'gather/scatter' editing. It 'search mode' it collects
lines that you wish to change in multiple files into a single 'edit-file'.
You then make the changes to the lines in the edit-file and then use the
tool to apply the changes to all of the source files in one go.

-- Search mode --

Usually search mode is enabled with the '-s' option. The given files
will be searched for lines matching the supplied pattern (Perl regular
expression), and they will be output in 'edit-file' format to standard
output, as follows:

  <filename>|<line number>|c|<text of the line>

The following options apply in search mode:

  -1    Only match the first occurence of the pattern in each file.
  
  -d delim
        Use the specified delimiter between fields in the output instead
        of the default '|' character (only useful if you somehow manage
        to have a '|' in your filenames).
  
  -i    Match the pattern case-insensitively.
    
  -R    Recursively descend into each directory found and search all files
        within each directory.
  
  -v    Print progress messages to standard error (only really useful in
        conjunction with '-R')

There are also two other special search modes enabled with '-f' and '-l'.
The '-d', '-R' and '-v' options can also be used with these modes.

  -f    Outputs an edit line for the first line of each file. This is useful
        for changing the path of interpreters in script files, for example
        changing '#!/bin/sh' to '#!/bin/bash' or if text needs to be pre-
        pended to every file.

  -l    Outputs an edit line for the last line of each file. This is useful
        if text needs to be appended to every file.

-- Replace mode --

With '-r' the tool operates in 'replace' mode and replaces (or otherwise
edits) lines according to the instructions found in the specified edit
file.

Lines have the same general form as output by the search process, that 
is, they contain four fields delimited by '|' characters. The first 
field is the name of the file to be edited, the second is the line 
number to be acted on, the third is the 'action' to be performed 
(explained below) and the last is the data for the line. The valid 
values for the action field are as follows: 

  c -- Change.
       Replace the specified line with the line data

  d -- Delete.
       Delete the specified line (any line data is ignored)

  i -- Insert.
       Output the line data immediately before the specified line.
       If more than one 'i' action appears for a particular line
       number then the data are accumulated and inserted into the
       output in the order in which they appear within the file.

  a -- Append.
       As for insert except that the data are output after the specified
       line rather than before.

The original file is backed up with a .bak extension prior to editing.

Note that replacements are done on the basis of line-number within the file,
so if the contents change between the time of generating an edit-file and
using it the results may be unpredictable.

If a delimiter was specified using '-d' at search time, the same delimiter
must be secified during the replace operation.

If the action field ends with '$' then no trailing new-line will be output.

The '-v' option can be used to print progress messages to standard error.
EOF
}