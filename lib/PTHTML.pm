############################################################
#
# PTHTML.pm
#
# Time-stamp: <2013-08-26 15:53:50 sekiya>
#
############################################################
# - ページ出力に特化
package PTHTML;

use constant{
    CONFIG_DIR        => 'conf',
};

# ローカルのモジュールを利用するため，ライブラリのパスを
# 明示的に設定
use lib '/usr/local/plack/tracing/lib';

use Config::Simple;

my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
my %CONFIG;
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

use Template;
my $TEMPLATE_CONFIG = {INCLUDE_PATH => $CONFIG{TEMPLATE_DIR}};

################################################
# ページ出力
################################################
sub render{
    my ($name, $arg) = @_;
    #my $tt = Template->new($TEMPLATE_CONFIG);
    my $tt = Template->new(INCLUDE_PATH => $CONFIG{TEMPLATE_DIR}, UNICODE  => 1, ENCODING => 'utf-8'); # TODO confirm
    my $out;
    $tt->process( $name, $arg, \$out );
    utf8::encode $out if utf8::is_utf8 $out; # TODO remove?
    return $out;
}

#######################################
# escape
#######################################
sub escape_text{
    my $s = shift;

    $s =~ s|\&|&amp;|g;
    $s =~ s|<|&lt;|g;
    $s =~ s|>|&gt;|g;
    $s =~ s|\"|&quot;|g;
    $s =~ s|\r\n|\n|g;
    $s =~ s|\r|\n|g;
    $s =~ s|\n|<br>|g;

    return $s;
}

1;
