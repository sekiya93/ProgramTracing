#########################################################
#
# CFIVE::DB.pm
#
# Created: Sun Apr 22 18:21:46 2012
# Time-stamp: <2013-08-23 16:36:51 sekiya>
#
#########################################################
# - rp1 上の東京学芸大学学生向け CFIVE を用いる

package CFIVE::DB;
use base qw/DBIx::MoCo::DataBase/;

#########################################################
# 初期設定
#########################################################

use constant{
    TOP_DIR => 'tracing',
};

use constant{
    CONFIG_FILE => 'conf/cfive.conf',
};

use Config::Simple;

my %CONFIG;

Config::Simple->import_from(CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

__PACKAGE__->dsn(
    'DBI:Pg:dbname=' . $CONFIG{DBName} . 
    ';host=' . $CONFIG{DBHost} . 
    ';sslmode=require'
    );
__PACKAGE__->username($CONFIG{DBUser});
# __PACKAGE__->password('bar');

1;
