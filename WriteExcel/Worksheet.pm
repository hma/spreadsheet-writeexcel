package Spreadsheet::WriteExcel::Worksheet;

###############################################################################
#
# Worksheet - A writer class for Excel Worksheets.
#
#
# Used in conjunction with Spreadsheet::WriteExcel
#
# Copyright 2000-2001, John McNamara, jmcnamara@cpan.org
#
# Documentation after __END__
#

require Exporter;

use strict;
use Carp;
use Spreadsheet::WriteExcel::BIFFwriter;
use Spreadsheet::WriteExcel::Format;
use Spreadsheet::WriteExcel::Formula;


use vars qw($VERSION @ISA);
@ISA = qw(Spreadsheet::WriteExcel::BIFFwriter);

$VERSION = '0.08';

###############################################################################
#
# new()
#
# Constructor. Creates a new Worksheet object from a BIFFwriter object
#
sub new {

    my $class               = shift;
    my $self                = Spreadsheet::WriteExcel::BIFFwriter->new();
    my $rowmax              = 65536; # 16384 in Excel 5
    my $colmax              = 256;
    my $strmax              = 255;

    $self->{_name}          = $_[0];
    $self->{_index}         = $_[1];
    $self->{_activesheet}   = $_[2];
    $self->{_firstsheet}    = $_[3];
    $self->{_url_format}    = $_[4];
    $self->{_parser}        = $_[5];

    $self->{_ext_sheets}    = [];
    $self->{_using_tmpfile} = 1;
    $self->{_filehandle}    = "";
    $self->{_fileclosed}    = 0;
    $self->{_offset}        = 0;
    $self->{_xls_rowmax}    = $rowmax;
    $self->{_xls_colmax}    = $colmax;
    $self->{_xls_strmax}    = $strmax;
    $self->{_dim_rowmin}    = $rowmax +1;
    $self->{_dim_rowmax}    = 0;
    $self->{_dim_colmin}    = $colmax +1;
    $self->{_dim_colmax}    = 0;
    $self->{_colinfo}       = [];
    $self->{_selection}     = [0, 0];


    bless $self, $class;
    $self->_initialize();
    return $self;
}


###############################################################################
#
# _initialize()
#
# Open a tmp file to store the majority of the Worksheet data. If this fails,
# for example due to write permissions, store the data in memory. This can be
# slow for large files.
#
sub _initialize {

    my $self    = shift;

    # Open tmp file for storing Worksheet data
    my $fh = IO::File->new_tmpfile();

    if (defined $fh) {
        # binmode file whether platform requires it or not
        binmode($fh);

        # Store filehandle
        $self->{_filehandle} = $fh;
    }
    else {
        # If new_tmpfile() fails store data in memory
        $self->{_using_tmpfile} = 0;
    }
}


###############################################################################
#
# _close()
#
# Add data to the beginning of the workbook (note the reverse order)
# and to the end of the workbook.
#
sub _close {

    my $self = shift;
    my $sheetnames = shift;
    my $num_sheets = scalar @$sheetnames;

    #
    # Prepend in reverse order!!
    #

    # Prepend the sheet dimensions
    $self->_store_dimensions();

    # Prepend EXTERNSHEET references
    for (my $i = $num_sheets; $i > 0; $i--) {
        my $sheetname = @{$sheetnames}[$i-1];
        $self->_store_externsheet($sheetname);
    }

    # Prepend the EXTERNCOUNT of external references.
    $self->_store_externcount($num_sheets);

    # Prepend the COLINFO records if they exist
    if (@{$self->{_colinfo}}){
        while (@{$self->{_colinfo}}) {
            my $arrayref = pop @{$self->{_colinfo}};
            $self->_store_colinfo(@$arrayref);
        }
        $self->_store_defcol();
    }

    # Prepend the BOF record
    $self->_store_bof(0x0010);

    # End of prepend. Read upwards from here.

    # Append
    $self->_store_window2();
    $self->_store_selection(@{$self->{_selection}});
    $self->_store_eof();
}


###############################################################################
#
# _append(), overloaded.
#
# Store Worksheet data in memory using the base class _append() or to a
# temporary file, the default.
#
sub _append {

    my $self = shift;

    if ($self->{_using_tmpfile}) {
        my $data    = join('', @_);
        print {$self->{_filehandle}} $data;
        $self->{_datasize} += length($data);
    }
    else {
        $self->SUPER::_append(@_);
    }
}


###############################################################################
#
# get_name().
#
# Retrieve the worksheet name.
#
sub get_name {

    my $self    = shift;

    return $self->{_name};
}


###############################################################################
#
# get_data().
#
# Retrieves data from memory in one chunk, or from disk in $buffer
# sized chunks.
#
sub get_data {

    my $self    = shift;
    my $buffer  = 4096;
    my $tmp;

    # Return data stored in memory
    if (defined $self->{_data}) {
        $tmp           = $self->{_data};
        $self->{_data} = undef;
        my $fh         = $self->{_filehandle};
        seek($fh, 0, 0) if $self->{_using_tmpfile};
        return $tmp;
    }

    # Return data stored on disk
    if ($self->{_using_tmpfile}) {
        return $tmp if read($self->{_filehandle}, $tmp, $buffer);
    }

    # No data to return
    return undef;
}


###############################################################################
#
# activate()
#
# Set this worksheet as the selected worksheet, i.e. the worksheet
# with its tab highlighted.
#
sub activate {

    my $self = shift;

    ${$self->{_activesheet}} = $self->{_index};
}


###############################################################################
#
# set_first_sheet()
#
# Set this worksheet as the first visible sheet. This is necessary
# when there are a large number of worksheets and the activated
# worksheet is not visible on the screen.
#
sub set_first_sheet {

    my $self = shift;

    ${$self->{_firstsheet}} = $self->{_index};
}


###############################################################################
#
# set_column($firstcol, $lastcol, $width, $format, $hidden)
#
# Set the width of a single column or a range of column.
# See also: _store_colinfo
#
sub set_column {

    my $self = shift;
    my $cell  = $_[0];

    # Check for a cell reference in A1 notation and substitute row and column
    if ($cell =~ /^\D/) {
        @_ = $self->_substitute_cellref(@_);
    }

    push @{$self->{_colinfo}}, [ @_ ];
}


###############################################################################
#
# set_col_width()
#
# This is a deprecated alias for set_column().
#
sub set_col_width {

    my $self = shift;

    $self->set_column(@_);
    carp("set_col_width() is deprecated, use set_column() instead") if $^W;
}


###############################################################################
#
# set_selection()
#
# Set which cell or cells are selected in a worksheet: see also the
# sub _store_selection
#
sub set_selection {

    my $self = shift;

    # Check for a cell reference in A1 notation and substitute row and column
    if ($_[0] =~ /^\D/) {
        @_ = $self->_substitute_cellref(@_);
    }

    $self->{_selection} = [ @_ ];
}


###############################################################################
#
# _XF()
#
# Returns an index to the XF record in the workbook
#
sub _XF {

    my $self = shift;

    if (ref($self)) {
        return $self->get_xf_index();
    }
    else {
        return 0x0F;
    }
}


###############################################################################
#
# write ($row, $col, $token, $format)
#
# Parse $token call appropriate write method. $row and $column are zero
# indexed. $format is optional.
#
# Returns: return value of called subroutine
#
sub write {

    my $self  = shift;

    # Check for a cell reference in A1 notation and substitute row and column
    if ($_[0] =~ /^\D/) {
        @_ = $self->_substitute_cellref(@_);
    }

    my $token = $_[2];

    # Match number
    if ($token =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/) {
        return $self->write_number(@_);
    }
    # Match http or ftp URL
    elsif ($token =~ m|^[fh]tt?p://|) {
        return $self->write_url(@_);
    }
    # Match mailto:
    elsif ($token =~ m/^mailto:/) {
        return $self->write_url(@_);
    }
    # Match formula
    elsif ($token =~ /^=/) {
        return $self->write_formula(@_);
    }
    # Match blank
    elsif ($token eq '') {
        splice @_, 2, 1; # remove the empty string from the parameter list
        return $self->write_blank(@_);
    }
    # Default: match string
    else {
        return $self->write_string(@_);
    }
}


###############################################################################
#
# _substitute_cellref()
#
# Substitute an Excel cell reference in A1 notation for  zero based row and
# column values in an argument list.
#
# Ex: ("A4", "Hello") is converted to (3, 0, "Hello").
#
sub _substitute_cellref {

    my $self = shift;
    my $cell = uc(shift);

    # Convert a column range: 'A:A' or 'B:G'
    if ($cell =~ /([A-I]?[A-Z]):([A-I]?[A-Z])/) {
        my (undef, $col1) =  $self->_cell_to_rowcol($1 .'1'); # Add a dummy row
        my (undef, $col2) =  $self->_cell_to_rowcol($2 .'1'); # Add a dummy row
        return $col1, $col2, @_;
    }

    # Convert a cell range: 'A1:B7'
    if ($cell =~ /\$?([A-I]?[A-Z]\$?\d+):\$?([A-I]?[A-Z]\$?\d+)/) {
        my ($row1, $col1) =  $self->_cell_to_rowcol($1);
        my ($row2, $col2) =  $self->_cell_to_rowcol($2);
        return $row1, $col1, $row2, $col2, @_;
    }

    # Convert a cell reference: 'A1' or 'AD2000'
    if ($cell =~ /\$?([A-I]?[A-Z]\$?\d+)/) {
        my ($row1, $col1) =  $self->_cell_to_rowcol($1);
        return $row1, $col1, @_;

    }

    croak("Unknown cell reference $cell ");
}


###############################################################################
#
# _cell_to_rowcol($cell_ref)
#
# Convert an Excel cell reference in A1 notation to a zero based row and column
# reference; converts C1 to (0, 2).
#
# Returns: row, column
#
sub _cell_to_rowcol {

    my $self = shift;
    my $cell = shift;

    $cell =~ /\$?([A-I]?[A-Z])\$?(\d+)/;

    my $col     = $1;
    my $row     = $2;

    # Convert base26 column string to number
    # All your base are belong to us.
    my @chars  = split //, $col;
    my $expn   = 0;
    $col       = 0;

    while (@chars) {
        my $char = pop(@chars); # LS char first
        $col += (ord($char) -ord('A') +1) * (26**$expn);
        $expn++;
    }

    # Convert 1-index to zero-index
    $row--;
    $col--;

    return $row, $col;
}




###############################################################################
#
# BIFF RECORDS
#


###############################################################################
#
# write_number($row, $col, $num, $format)
#
# Write a double to the specified row and column (zero indexed).
# An integer can be written as a double. Excel will display an
# integer. $format is optional.
#
# Returns  0 : normal termination
#         -1 : insufficient number of arguments
#         -2 : row or column out of range
#
sub write_number {

    my $self = shift;

    # Check for a cell reference in A1 notation and substitute row and column
    if ($_[0] =~ /^\D/) {
        @_ = $self->_substitute_cellref(@_);
    }

    if (@_ < 3) { return -1 }               # Check the number of args

    my $record    = 0x0203;                 # Record identifier
    my $length    = 0x000E;                 # Number of bytes to follow

    my $row       = $_[0];                  # Zero indexed row
    my $col       = $_[1];                  # Zero indexed column
    my $num       = $_[2];
    my $xf        = _XF($_[3]);             # The cell format

    # Check that row and col are valid and store max and min values
    if ($row >= $self->{_xls_rowmax}) { return -2 }
    if ($col >= $self->{_xls_colmax}) { return -2 }
    if ($row <  $self->{_dim_rowmin}) { $self->{_dim_rowmin} = $row }
    if ($row >  $self->{_dim_rowmax}) { $self->{_dim_rowmax} = $row }
    if ($col <  $self->{_dim_colmin}) { $self->{_dim_colmin} = $col }
    if ($col >  $self->{_dim_colmax}) { $self->{_dim_colmax} = $col }

    my $header    = pack("vv",  $record, $length);
    my $data      = pack("vvv", $row, $col, $xf);
    my $xl_double = pack("d",   $num);

    if ($self->{_byte_order}) { $xl_double = reverse $xl_double }

    $self->_append($header, $data, $xl_double);

    return 0;
}


###############################################################################
#
# write_string ($row, $col, $string, $format)
#
# Write a string to the specified row and column (zero indexed).
# NOTE: there is an Excel 5 defined limit of 255 characters.
# $format is optional.
# Returns  0 : normal termination
#         -1 : insufficient number of arguments
#         -2 : row or column out of range
#         -3 : long string truncated to 255 chars
#
sub write_string {

    my $self = shift;

    # Check for a cell reference in A1 notation and substitute row and column
    if ($_[0] =~ /^\D/) {
        @_ = $self->_substitute_cellref(@_);
    }

    if (@_ < 3) { return -1 }               # Check the number of args

    my $record    = 0x0204;                 # Record identifier
    my $length    = 0x0008 + length($_[2]); # Bytes to follow

    my $row       = $_[0];                  # Zero indexed row
    my $col       = $_[1];                  # Zero indexed column
    my $strlen    = length($_[2]);
    my $str       = $_[2];
    my $xf        = _XF($_[3]);             # The cell format

    my $str_error = 0;

    # Check that row and col are valid and store max and min values
    if ($row >= $self->{_xls_rowmax}) { return -2 }
    if ($col >= $self->{_xls_colmax}) { return -2 }
    if ($row <  $self->{_dim_rowmin}) { $self->{_dim_rowmin} = $row }
    if ($row >  $self->{_dim_rowmax}) { $self->{_dim_rowmax} = $row }
    if ($col <  $self->{_dim_colmin}) { $self->{_dim_colmin} = $col }
    if ($col >  $self->{_dim_colmax}) { $self->{_dim_colmax} = $col }

    if ($strlen > $self->{_xls_strmax}) { # LABEL must be < 255 chars
        $str       = substr($str, 0, $self->{_xls_strmax});
        $length    = 0x0008 + $self->{_xls_strmax};
        $strlen    = $self->{_xls_strmax};
        $str_error = -3;
    }

    my $header    = pack("vv",   $record, $length);
    my $data      = pack("vvvv", $row, $col, $xf, $strlen);

    $self->_append($header, $data, $str);

    return $str_error;
}


###############################################################################
#
# write_blank($row, $col, $format)
#
# Write a blank cell to the specified row and column (zero indexed).
# A blank cell is used to specify formatting without adding a string
# or a number. $format is optional.
#
# Returns  0 : normal termination
#         -1 : insufficient number of arguments
#         -2 : row or column out of range
#
sub write_blank {

    my $self = shift;

    # Check for a cell reference in A1 notation and substitute row and column
    if ($_[0] =~ /^\D/) {
        @_ = $self->_substitute_cellref(@_);
    }

    if (@_ < 2) { return -1 }               # Check the number of args

    my $record    = 0x0201;                 # Record identifier
    my $length    = 0x0006;                 # Number of bytes to follow

    my $row       = $_[0];                  # Zero indexed row
    my $col       = $_[1];                  # Zero indexed column
    my $xf        = _XF($_[2]);             # The cell format

    # Check that row and col are valid and store max and min values
    if ($row >= $self->{_xls_rowmax}) { return -2 }
    if ($col >= $self->{_xls_colmax}) { return -2 }
    if ($row <  $self->{_dim_rowmin}) { $self->{_dim_rowmin} = $row }
    if ($row >  $self->{_dim_rowmax}) { $self->{_dim_rowmax} = $row }
    if ($col <  $self->{_dim_colmin}) { $self->{_dim_colmin} = $col }
    if ($col >  $self->{_dim_colmax}) { $self->{_dim_colmax} = $col }

    my $header    = pack("vv",  $record, $length);
    my $data      = pack("vvv", $row, $col, $xf);

    $self->_append($header, $data);

    return 0;
}


###############################################################################
#
# write_formula($row, $col, $formula, $format)
#
# Write a formula to the specified row and column (zero indexed).
# The textual representation of the formula is passed to the parser in
# Formula.pm which returns a packed binary string.
#
# $format is optional.
#
# Returns  0 : normal termination
#         -1 : insufficient number of arguments
#         -2 : row or column out of range
#
sub write_formula{

    my $self = shift;

    # Check for a cell reference in A1 notation and substitute row and column
    if ($_[0] =~ /^\D/) {
        @_ = $self->_substitute_cellref(@_);
    }

    if (@_ < 3) { return -1 }   # Check the number of args

    my $record    = 0x0006;     # Record identifier
    my $length;                 # Bytes to follow

    my $row       = $_[0];      # Zero indexed row
    my $col       = $_[1];      # Zero indexed column
    my $formula   = $_[2];      # The formula text string


    # Excel normally stores the last calculated value of the formula in $num.
    # Clearly we are not in a position to calculate this a priori. Instead
    # we set $num to zero and set the option flags in $grbit to ensure
    # automatic calculation of the formula when the file is opened.
    #
    my $xf        = _XF($_[3]); # The cell format
    my $num       = 0x00;       # Current value of formula
    my $grbit     = 0x03;       # Option flags
    my $chn       = 0x0000;     # Must be zero


    # Check that row and col are valid and store max and min values
    if ($row >= $self->{_xls_rowmax}) { return -2 }
    if ($col >= $self->{_xls_colmax}) { return -2 }
    if ($row <  $self->{_dim_rowmin}) { $self->{_dim_rowmin} = $row }
    if ($row >  $self->{_dim_rowmax}) { $self->{_dim_rowmax} = $row }
    if ($col <  $self->{_dim_colmin}) { $self->{_dim_colmin} = $col }
    if ($col >  $self->{_dim_colmax}) { $self->{_dim_colmax} = $col }


    # Strip the = sign at the beginning of the formula string
    $formula =~ s(^=)();

    # Parse the formula using the parser in Formula.pm
    my $parser = $self->{_parser};
    $formula   = $parser->parse_formula($formula);


    my $formlen = length($formula); # Length of the binary string
    $length     = 0x16 + $formlen;  # Length of the record data

    my $header    = pack("vv",      $record, $length);
    my $data      = pack("vvvdvVv", $row, $col, $xf, $num,
                                    $grbit, $chn, $formlen);

    $self->_append($header, $data, $formula);

    return 0;
}


###############################################################################
#
# write_url($row, $col, $url, $string, $format )
#
# Write a hyperlink. This is comprised of two elements: the visible label and
# the invisible link. The visible label is the same as the link unless an
# alternative string is specified. The label is written using the
# write_string() method. Therefore the 255 characters string limit applies.
# $string and $format are optional.
#
# Returns  0 : normal termination
#         -1 : insufficient number of arguments
#         -2 : row or column out of range
#         -3 : long string truncated to 255 chars
#
sub write_url {
    my $self = shift;

    # Check for a cell reference in A1 notation and substitute row and column
    if ($_[0] =~ /^\D/) {
        @_ = $self->_substitute_cellref(@_);
    }

    if (@_ < 3) { return -1 }                    # Check the number of args

    my $record  = 0x01B8;                        # Record identifier
    my $length  = 0x0034 + 2*(1+length($_[2]));  # Bytes to follow

    my $row     = $_[0];                         # Zero indexed row
    my $col     = $_[1];                         # Zero indexed column
    my $url     = $_[2];                         # URL string
    my $str     = $_[3] || $_[2];                # Alternative label
    my $xf      = $_[4] || $self->{_url_format}; # The cell format


    # Write the visible label using the write_string() method.
    my $str_error = $self->write_string($row, $col, $str, $xf);
    return $str_error if $str_error == -2;


    # Pack the header data
    my $header  = pack("vv",   $record, $length);
    my $data    = pack("vvvv", $row, $row, $col, $col);


    # Pack the undocumented part of the hyperlink stream, 40 bytes.
    my $unknown = "D0C9EA79F9BACE118C8200AA004BA90B02000000";
    $unknown   .= "03000000E0C9EA79F9BACE118C8200AA004BA90B";
    my $stream  = pack("H*", $unknown);


    # Convert URL to a null terminated wchar string
    $url        = join("\0", split('', $url));
    $url        = $url . "\0\0\0";


    # Pack the length of the URL
    my $url_len = pack("V", length($url));


    # Write the packed data
    $self->_append($header, $data);
    $self->_append($stream);
    $self->_append($url_len);
    $self->_append($url);

    return $str_error;

}


###############################################################################
#
# set_row($row, $height, $XF)
#
# This method is used to set the height and XF format for a row.
# Writes the  BIFF record ROW.
#
sub set_row {

    my $self        = shift;
    my $record      = 0x0208;               # Record identifier
    my $length      = 0x0010;               # Number of bytes to follow

    my $rw          = $_[0];                # Row Number
    my $colMic      = 0x0000;               # First defined column
    my $colMac      = 0x0000;               # Last defined column
    my $miyRw;                              # Row height
    my $irwMac      = 0x0000;               # Used by Excel to optimise loading
    my $reserved    = 0x0000;               # Reserved
    my $grbit       = 0x01C0;               # Option flags. (monkey) see $1 do
    my $ixfe        = _XF($_[2]);           # XF index

    # Use set_row($row, undef, $XF) to set XF without setting height
    if (defined ($_[1])) {
        $miyRw = $_[1] *20;
    }
    else {
        $miyRw = 0xff;
    }

    my $header   = pack("vv",       $record, $length);
    my $data     = pack("vvvvvvvv", $rw, $colMic, $colMac, $miyRw,
                                    $irwMac,$reserved, $grbit, $ixfe);

    $self->_append($header, $data);
}


###############################################################################
#
# _store_dimensions()
#
# Writes Excel DIMENSIONS to define the area in which there is data.
#
sub _store_dimensions {

    my $self      = shift;
    my $record    = 0x0000;               # Record identifier
    my $length    = 0x000A;               # Number of bytes to follow
    my $row_min   = $self->{_dim_rowmin}; # First row
    my $row_max   = $self->{_dim_rowmax}; # Last row plus 1
    my $col_min   = $self->{_dim_colmin}; # First column
    my $col_max   = $self->{_dim_colmax}; # Last column plus 1
    my $reserved  = 0x0000;               # Reserved by Excel

    my $header    = pack("vv",    $record, $length);
    my $data      = pack("vvvvv", $row_min, $row_max,
                                  $col_min, $col_max, $reserved);
    $self->_prepend($header, $data);
}


###############################################################################
#
# _store_window2()
#
# Write BIFF record Window2.
#
sub _store_window2 {

    my $self    = shift;
    my $record  = 0x023E;     # Record identifier
    my $length  = 0x000A;     # Number of bytes to follow

    my $grbit   = 0x00B6;     # Option flags
    my $rwTop   = 0x0000;     # Top row visible in window
    my $colLeft = 0x0000;     # Leftmost column visible in window
    my $rgbHdr  = 0x00000000; # Row/column heading and gridline color

    if (${$self->{_activesheet}} == $self->{_index}) {
        $grbit = 0x06B6;
    }

    my $header  = pack("vv",   $record, $length);
    my $data    = pack("vvvV", $grbit, $rwTop, $colLeft, $rgbHdr);

    $self->_append($header, $data);
}


###############################################################################
#
# _store_defcol()
#
# Write BIFF record DEFCOLWIDTH if COLINFO records are in use.
#
sub _store_defcol {

    my $self     = shift;
    my $record   = 0x0055;      # Record identifier
    my $length   = 0x0002;      # Number of bytes to follow

    my $colwidth = 0x0008;      # Default column width

    my $header   = pack("vv", $record, $length);
    my $data     = pack("v",  $colwidth);

    $self->_prepend($header, $data);
}


###############################################################################
#
# _store_colinfo($firstcol, $lastcol, $width, $format, $hidden)
#
# Write BIFF record COLINFO to define column widths
#
# Note: The SDK says the record length is 0x0B but Excel writes a 0x0C
# length record.
#
sub _store_colinfo {

    my $self     = shift;
    my $record   = 0x007D;          # Record identifier
    my $length   = 0x000B;          # Number of bytes to follow

    my $colFirst = $_[0] || 0;      # First formatted column
    my $colLast  = $_[1] || 0;      # Last formatted column
    my $coldx    = $_[2] || 8.43;   # Col width, 8.43 is Excel default

    $coldx       += 0.72;           # Fudge. Excel subtracts 0.72 !?
    $coldx       *= 256;            # Convert to units of 1/256 of a char


    my $ixfe     = _XF($_[3]);      # XF
    my $grbit    = $_[4] || 0;      # Option flags
    my $reserved = 0x00;            # Reserved

    my $header   = pack("vv",     $record, $length);
    my $data     = pack("vvvvvC", $colFirst, $colLast, $coldx,
                                  $ixfe, $grbit, $reserved);

    $self->_prepend($header, $data);
}


###############################################################################
#
# _store_selection($first_row, $first_col, $last_row, $last_col)
#
# Write BIFF record SELECTION.
#
sub _store_selection {

    my $self     = shift;
    my $record   = 0x001D;              # Record identifier
    my $length   = 0x000F;              # Number of bytes to follow

    my $pnn      = 3;                   # Pane position
    my $rwAct    = $_[0];               # Active row
    my $colAct   = $_[1];               # Active column
    my $irefAct  = 0;                   # Active cell ref
    my $cref     = 1;                   # Number of refs

    my $rwFirst  = $_[0];               # First row in reference
    my $colFirst = $_[1];               # First col in reference
    my $rwLast   = $_[2] || $rwFirst;   # Last  row in reference
    my $colLast  = $_[3] || $colFirst;  # Last  col in reference

    # Swap last row/col for first row/col as necessary
    if ($rwFirst > $rwLast) {
        ($rwFirst, $rwLast) = ($rwLast, $rwFirst);
    }

    if ($colFirst > $colLast) {
        ($colFirst, $colLast) = ($colLast, $colFirst);
    }


    my $header   = pack("vv",           $record, $length);
    my $data     = pack("CvvvvvvCC",    $pnn, $rwAct, $colAct,
                                        $irefAct, $cref,
                                        $rwFirst, $rwLast,
                                        $colFirst, $colLast);

    $self->_append($header, $data);
}


###############################################################################
#
# _store_externcount($count)
#
# Write BIFF record EXTERNCOUNT to indicate the number of external sheet
# references in a worksheet.
#
# Excel only stores references to external sheets that are used in formulas.
# For simplicity we store references to all the sheets in the workbook
# regardless of whether they are used or not. This reduces the overall
# complexity and eliminates the need for a two way dialogue between the formula
# parser the worksheet objects.
#
sub _store_externcount {

    my $self     = shift;
    my $record   = 0x0016;          # Record identifier
    my $length   = 0x0002;          # Number of bytes to follow

    my $cxals    = $_[0];           # Number of external references

    my $header   = pack("vv", $record, $length);
    my $data     = pack("v",  $cxals);

    $self->_prepend($header, $data);
}


###############################################################################
#
# _store_externsheet($sheetname)
#
#
# Writes the Excel BIFF EXTERNSHEET record. These references are used by
# formulas. A formula references a sheet name via an index. Since we store a
# reference to all of the external worksheets the EXTERNSHEET index is the same
# as the worksheet index.
#
sub _store_externsheet {

    my $self      = shift;

    my $record    = 0x0017;         # Record identifier
    my $length;                     # Number of bytes to follow

    my $sheetname = $_[0];          # Worksheet name
    my $cch;                        # Length of sheet name
    my $rgch;                       # Filename encoding

    # References to the current sheet are encoded differently to references to
    # external sheets.
    #
    if ($self->{_name} eq $sheetname) {
        $sheetname = '';
        $length    = 0x02;  # The following 2 bytes
        $cch       = 1;     # The following byte
        $rgch      = 0x02;  # Self reference
    }
    else {
        $length    = 0x02 + length($_[0]);
        $cch       = length($sheetname);
        $rgch      = 0x03;  # Reference to a sheet in the current workbook
    }

    my $header     = pack("vv",  $record, $length);
    my $data       = pack("CC", $cch, $rgch);

    $self->_prepend($header, $data, $sheetname);
}


1;


__END__


=head1 NAME

Worksheet - A writer class for Excel Worksheets.

=head1 SYNOPSIS

See the documentation for Spreadsheet::WriteExcel

=head1 DESCRIPTION

This module is used in conjunction with Spreadsheet::WriteExcel.

=head1 AUTHOR

John McNamara jmcnamara@cpan.org

=head1 COPYRIGHT

� MM-MMI, John McNamara.

All Rights Reserved. This module is free software. It may be used, redistributed and/or modified under the same terms as Perl itself.