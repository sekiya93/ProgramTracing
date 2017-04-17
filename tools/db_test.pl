#!/usr/bin/perl -w
############################################################
#
# データベースの接続テスト (2014-04-29)
#
# Time-stamp: <2014-05-10 21:19:35 sekiya>
#
############################################################
use strict;
use warnings;
# ローカルのモジュールを利用するため，ライブラリのパスを
# 明示的に設定
use lib '/usr/local/plack/tracing/lib';

use utf8;
use DBI;
use PTDB;

my $teng = PTDB->new(
    {
	connect_info => ['DBI:Pg:dbname=ptdb;host=127.0.0.1;', 'ptdb']
    });

eval{
    $teng->insert('ptuser',
		  {
		      userid      => 'sekiya',
		  password    => 'test',
		  fullname    => 'SEKIYA Takayuki',
		  fullname_ja => '関谷 貴之',
		  mail_address => 'sekiya@ecc.u-tokyo.ac.jp',
		  realm => 'gakugei',
		  register_date => 'now',
		  update_date => 'now'
	      }
    );
};
if($@){
    printf(STDERR "ERROR: %s", $@);
}

