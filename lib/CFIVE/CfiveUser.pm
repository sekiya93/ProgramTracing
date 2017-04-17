########################################
#
#  CFIVE::CfiveUser.pm
#  
#  Created: Sun Apr 22 18:32:24 2012
#  Time-stamp: <2012-04-22 18:35:25 sekiya>
#
########################################

package CFIVE::CfiveUser;
use base qw/CFIVE::MoCo/;

__PACKAGE__->table('cfive_user');
__PACKAGE__->primary_keys(qw/user_name/);

1;
