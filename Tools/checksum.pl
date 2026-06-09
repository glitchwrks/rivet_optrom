@rem = '--*-Perl-*--
@echo off
perl -x -S %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
@rem ';
#!perl
#
# Add checksum byte(s) to PC Option ROM image
#
# On Windows, this file can be renamed to a batch file and invoked directly (for example, "C:\>checksum filename")
#

#
# XTIDE Universal BIOS and Associated Tools
# Copyright (C) 2009-2010 by Tomi Tilli, 2011-2026 by XTIDE Universal BIOS Team.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# Visit http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
#

$ARGV[0] ne "" || die "usage: checksum filename\n";

$ok = open ( FILE, "+<".$ARGV[0] );
if( $ok == 0 )
{
	die "ERROR: failed to open ".$ARGV[0]."\n";
}

binmode FILE;
seek( FILE, 2, 0 );
read( FILE, $biosSize, 1 );
$biosSize = ord($biosSize) << 9;
if( $biosSize & 2047 )
{
	die "ERROR: image is not a valid PC Option ROM BIOS\n";
}

seek( FILE, 0, 0 );
while( ($n = read( FILE, $d, 1 )) != 0 )
{
	$cs = ($cs + ord($d)) & 255;
	$bytes++;
}
$oldBytes = $bytes;

if( $bytes > $biosSize - 1 )
{
	die "ERROR: image is bigger than ".($biosSize-1).": $bytes\n";
}

$fixzero = chr(0);
$fixl = ($cs == 0 ? 0 : 256 - $cs);

#
# Compatibility fix for 3Com 3C503 cards. They use 8 KB ROMs and return 8080h as the last word of the ROM.
#
if( $biosSize == 8192 ) {
	if( $bytes <= $biosSize - 3 ) {
		while( $bytes < $biosSize - 3 ) {
			print FILE $fixzero;
			$bytes++;
		}
		$fix = chr($fixl).chr($cs);
		print FILE $fix;
		$bytes += 2;
	} elsif ( $bytes < $biosSize - 1 ) {
		print "Warning! ".$ARGV[0]." cannot be used on a 3Com 3C503 card unless it can be checksummed manually!\n";
	} else {
		print "Warning! ".$ARGV[0]." cannot be used on a 3Com 3C503 card!\n";
	}
}

while( $bytes < $biosSize - 1 )
{
	print FILE $fixzero;
	$bytes++;
}

$fix = chr($fixl);
print FILE $fix;

close FILE;

open FILE, "<".$ARGV[0];
binmode FILE;
$cs = 0;
while( ($n = read( FILE, $d, 1 )) != 0 )
{
	$cs = ($cs + ord($d)) & 255;
	$newBytes++;
}
$cs == 0 || die "ERROR: checksum verification failed\n";

print "checksum: ".$ARGV[0].": $oldBytes bytes before, $newBytes bytes after\n";

__DATA__
:endofperl
