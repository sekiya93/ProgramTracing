############################################################
#
# PTDB.pm
#
# Time-stamp: <2014-05-10 21:14:59 sekiya>
#
############################################################
package PTDB;
use parent 'Teng';

sub handle_error {
    my ($self, $stmt, $bind, $reason) = @_;
    $reason =~ s/\r?\n//;
    require Data::Dumper;
    local $Data::Dumper::Indent = 0;
    local $Data::Dumper::Terse  = 1;
    local $Data::Dumper::Useqq  = 1;
    local $Data::Dumper::Pair   = '=>';
    Carp::croak sprintf '%s %s %s', $reason, $stmt, Data::Dumper::Dumper($bind);
}

1;
