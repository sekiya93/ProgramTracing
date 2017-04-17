#!/usr/bin/perl -w
####################################################
# 
# change_variable_in_simple_loop.pl
#
# Usage: $0 ruby_program converted_program
#
# Time-stamp: <2013-08-07 18:08:39 sekiya>
#########################################################
#
# - for ループ内で，単純に increment するような代入式が
#   あると，制御変数だと誤解してしまう
# - 但し，ループ内が「代入式1個」の場合のみ発生する
#
# (例) 変数 a を制御変数 i に変換(誤解?)
# for i in 1..a
#   ans = ans + a
# end
# -> 
# for i in 1..a
#   ans = ans + i
# end 

############################################################
# 初期設定
############################################################
#use lib '/usr/local/plack/tracing/lib';
use lib './lib';

use strict;
use ParseRuby;
use Data::Dumper;
use FileHandle;

my $PARSE_RUBY = ParseRuby->new();

# デバッグ
my $DEBUG = 0;

# 変換された場合は1
my $CHANGED = 0;

############################################################
# 変換: ループ内の変数を，for ループの制御変数に置き換える
############################################################
# - 二重ループは... 取りあえず考えないか
sub change_variables_in_loop{
    my ($ruby_hash) = @_;

    my $caller_p = $ruby_hash->{predicate};
    # printf(STDERR "DEBUG: caller (%s)\n", $caller_p);

    if($PARSE_RUBY->is_block($ruby_hash) ||
       $PARSE_RUBY->is_method_definition($ruby_hash) ||
       $PARSE_RUBY->is_scope($ruby_hash)){
	#
	# メソッド定義やブロックの場合
	#

	foreach my $sentence_hash ($PARSE_RUBY->get_all_sentences($ruby_hash)){
	    # printf STDERR "DEBUG:\t\trest(%s) in %s at %d\n", $sentence_hash->{predicate}, $caller_p, $index;
	    change_variables_in_loop($sentence_hash);
	}
    }elsif($PARSE_RUBY->is_for_loop($ruby_hash)){
	#
	# for 文の場合
	#

	# 制御変数
	my $control_var = $PARSE_RUBY->get_control_variable_of_for_loop($ruby_hash);
	# 最大値(に相当する変数)
	# - 最大値が変数として与えられていることを前提とする
	my $max_var     = $PARSE_RUBY->get_max_range_of_for_loop($ruby_hash);

	# ループの中身
	my $loop = $PARSE_RUBY->get_contents_of_for_loop($ruby_hash);

	# ループの中身が，代入式1つの場合のみ変換処理を行う 
	# - ループの中身がより複雑な命令の場合は，誤解は生じないだろうとの
	#   推測
	if($PARSE_RUBY->is_assignment($loop)){
	    my ($h, $result) = $PARSE_RUBY->replace_variable_into($loop, $max_var, $control_var);
	    $CHANGED = 1 if($result);
	}
    }elsif($PARSE_RUBY->is_if($ruby_hash)){
	#
	# if
	#

	my $then_clause = $PARSE_RUBY->get_then_clause($ruby_hash);
	change_variables_in_loop($then_clause);

	# else があれば
	my $else_clause = $PARSE_RUBY->get_else_clause($ruby_hash);
	return if(!defined($else_clause));
	change_variables_in_loop($else_clause);
    }
}

############################################################
# メイン
############################################################
my $str = $PARSE_RUBY->generate_ruby_s_expression($ARGV[0]);

# print STDERR "DEBUG: (original) $str\n";
my $hash_ref = $PARSE_RUBY->parse_s_expression($str);

# print "*** S-expression (original) ***\n";
# print $PARSE_RUBY->s_reverse_parse($hash_ref);

print STDERR "\n\n*** Ruby  (original) ***\n";
print STDERR $PARSE_RUBY->reverse_parse($hash_ref) . "\n";

change_variables_in_loop($hash_ref);

# print "*** S-expression (change_variabele_in_loop) ***\n";
# print $PARSE_RUBY->s_reverse_parse($hash_ref);

print STDERR "\n\n*** Ruby  (change_variabele_in_loop) ***\n";
print STDERR $PARSE_RUBY->reverse_parse($hash_ref) . "\n";

if($CHANGED){
    # 変換された場合
    print STDERR "Converted.\n";
    my $converted_file = $ARGV[1];
    unlink($converted_file) if(-f $converted_file);

    my $fh = FileHandle->new($converted_file, O_WRONLY|O_CREAT);
    $fh->printf("%s\n", $PARSE_RUBY->reverse_parse($hash_ref));
    $fh->close();
}else{
    # 変換されなかった場合
    print STDERR "Not converted.\n";
    exit 1;
}


