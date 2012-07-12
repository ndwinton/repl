#!/usr/bin/perl
#
# Gather/Scatter editing
#
# $Id: repl.pl,v 1.3 2003/05/14 09:17:02 wintonn Exp $
#
# Neil Winton (neil@winton.org.uk)
#
# Copyright (c) 1999, 2002, 2003 by Neil Winton. All rights reserved.
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

getopts("1d:filRr:s:v");

# Set the default delimiter (|) over-ride with -d if necessary

$Delim = "|";
$Delim = $opt_d if ($opt_d ne '');
die "$0: Delimiter must be a single character\n" unless (length($Delim) == 1);

# If -s is specified then search for the specified pattern in the specified
# files.

if ($opt_s ne '' || $opt_l ne '' || $opt_f ne '')
{
    # If -R is specified then recurse into any directories specified
    # looking for (non-binary) files and add them into the ARGV array.

    if ($opt_R)
    {
	@ARGV = RecurseDirs(@ARGV);
    }
    Search($opt_s);
}

# If -r is specified then apply the edits from the specified file

elsif ($opt_r ne '')
{
    Replace($opt_r);
}

# Must specify one of -s or -r!

else
{
    Usage();
}

# Search all files named in the @ARGV array. If the search expression is
# found output a line of the following form:
#
#   <filename>|<line number>|c|<text of the line>
#
# The delimiter character can be over-ridden with -d if necessary.
# If there is no new-line then the 'c' will be suffixed with a '$'.

sub Search
{
    my ($expr) = @_;
    my ($file, $iflag, $test, @test);
 
    $iflag = "i" if ($opt_i);

    push(@test, '/$expr/o' . $iflag) if ($expr ne '');
    push(@test, '$. == 1') if ($opt_f);
    push(@test, 'eof(ARGV)') if ($opt_l);
    $test = join(' || ', @test);

eval <<EOT;
    \$seen = 0;
    while (<>)
    {
	if (!\$seen && $test)
	{
	    if (/\\n/)
	    {
		\$eol = '';
		\$nl = "";
	    }
	    else
	    {
		\$eol = '\$';
		\$nl = "\\n";
	    }
	    print "\$ARGV${Delim}\$.${Delim}c\$eol${Delim}\$_\$nl";
	    \$seen = '$opt_1';
	}
        if (eof(ARGV))
	{
	    \$. = 0;
	    \$seen = 0;
	}
    }
EOT
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
#	    Replace the specified line with the line data
#
#   d -- Delete.
#	    Delete the specified line (any line data is ignored)
#
#   i -- Insert.
#	    Output the line data immediately before the specified line.
#	    If more than one "i" action appears for a particular line then
#	    the data are accumulated and inserted into the output in the
#	    order in which they appear within the file.
#
#   a -- Append.
#	    As for insert except that the data are output after the specified
#	    line rather than before.
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
    while (<IN>)
    {
	# Match the edit control lines -- ignore others

	if (($file, $num, $action, $eol, $data) = /^([^\Q$Delim\E]+)\Q$Delim\E(\d+)\Q$Delim\E(.)(\$?)\Q$Delim\E(.*)/o)
	{
	    push(@{$repInfo{$file}[$num]{$action}}, $data . ($eol eq '$' ? "" : "\n"));
	}
	else
	{
	    print STDERR "$0: Bad edit line ($file, $num, $action, $data) -- ignored: $_"
	}
    }
    close(IN);

    foreach $file (sort(keys(%repInfo)))
    {
	print STDERR "$file\n" if ($opt_v);

	if ($file ne "-")
	{
	    die "$0: Can't read $file ($!)\n" unless (-r $file);
	    die "$0: Can't rename $file to $file.bak ($!)\n" unless rename($file, "$file.bak");
	    die "$0: Can't open $file.bak ($!)\n", unless open(IN, "<$file.bak");
	}
	die "$0: Can't create $file ($!)\n" unless open(OUT, ">$file");

	$num = 1;

	while (<IN>)
	{
	    # Insert before current line

	    if (defined($repInfo{$file}[$num]{i}))
	    {
		foreach $line (@{$repInfo{$file}[$num]{i}})
		{
		    print OUT $line;
		}
	    }

	    # Delete current line

	    if (defined($repInfo{$file}[$num]{d}))
	    {
		$_ = '';
	    }

	    # Change current line

	    if (defined($repInfo{$file}[$num]{c}))
	    {
		$_ = '';
		foreach $line (@{$repInfo{$file}[$num]{c}})
		{
		    $_ .= $line;
		}
	    }

	    # Output current line

	    print OUT $_;

	    # Append after current line

	    if (defined($repInfo{$file}[$num]{a}))
	    {
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
    print STDERR "Usage: $0 [-1filRv] [-d delim] -s pattern file ... > edit-file\n" .
		 "  or   $0 [-v] [-d delim] -r edit-file\n";
    exit 1;
}

# RecurseDirs
#
# Recursively search directories building a list of non-binary files

sub RecurseDirs
{
    my (@files, $entry);
    local (*DIR);

    foreach (@_)
    {
	if (-d $_)
	{
	    next unless opendir(DIR, $_);
	    foreach $entry (readdir(DIR))
	    {
		next if ($entry eq '.' || $entry eq '..');
		push(@files, RecurseDirs($_ . "/" . $entry));
	    }
	    closedir(DIR);
	}
	elsif (!-B $_)
	{
	    push(@files, $_);
	}
    }

    @files;
}
