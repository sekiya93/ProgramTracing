########################################
#
#  CFIVE::MoCo.pm
#  
#  Created: Sun Apr 22 18:31:22 2012
#  Time-stamp: <2012-04-22 18:32:09 sekiya>
#
########################################
package CFIVE::MoCo;
use strict;
use warnings;
use base qw/DBIx::MoCo/; # Inherit DBIx::MoCo;
use CFIVE::DB;

__PACKAGE__->db_object('CFIVE::DB');

1;
