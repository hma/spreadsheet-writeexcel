#!/usr/bin/perl -w

###############################################################################
#
# Example of how to use the Spreadsheet::WriteExcel merge_cells() workbook
# method with with complex formatting and rotation.
#
## reverse('�'), September 2002, John McNamara, jmcnamara@cpan.org
#

use strict;
use Spreadsheet::WriteExcel;

# Create a new workbook and add a worksheet
my $workbook  = Spreadsheet::WriteExcel->new('merge5.xls');
my $worksheet = $workbook->addworksheet();


# Increase the cell size of the merged cells to highlight the formatting.
$worksheet->set_row($_, 60)         for (3..8);
$worksheet->set_column($_, $_ , 15) for (1,3,5);


###############################################################################
#
# Rotation 1, letters run from top to bottom
#
my $format1 = $workbook->addformat(
                                    border      => 6,
                                    bold        => 1,
                                    color       => 'red',
                                    valign      => 'vcentre',
                                    align       => 'centre',
                                    rotation    => 1,
                                  );


$worksheet->merge_range('B4:B9', 'Rotation 1: Top to bottom', $format1);


###############################################################################
#
# Rotation 2, 90� anticlockwise
#
my $format2 = $workbook->addformat(
                                    border      => 6,
                                    bold        => 1,
                                    color       => 'red',
                                    valign      => 'vcentre',
                                    align       => 'centre',
                                    rotation    => 2,
                                  );


$worksheet->merge_range('D4:D9', 'Rotation 2: 90� anticlockwise', $format2);



###############################################################################
#
# Rotation 3, 90� clockwise
#
my $format3 = $workbook->addformat(
                                    border      => 6,
                                    bold        => 1,
                                    color       => 'red',
                                    valign      => 'vcentre',
                                    align       => 'centre',
                                    rotation    => 3,
                                  );


$worksheet->merge_range('F4:F9', 'Rotation 3: 90� clockwise', $format3);
