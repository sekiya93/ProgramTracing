#!/usr/bin/perl -w
################################################
# 
# change_variable_in_condition2.pl
#
# Usage: $0 ruby_program converted_program
#
# Created: Mon Apr 30 22:24:30 2012
# Time-stamp: <2012-04-30 22:24:23 sekiya>
#
################################################
#
# - for ループ内での if-then の条件式の変数を誤解する
# -- 代入式など条件式以外はどのように解釈する?
#
# (例) 制御変数 i を変数 a に変換(誤解?)
# a7.rb
# ...
#  for i in 1..a
#     if i > 3 
#       ans = ans + i
#     else
#       ans = ans - i
#     end
#   end
# -> 
#  for i in 1..a
#     if a > 3  # <- 制御変数 i を一般の変数 a に置換
#       ans = ans + i
#     else
#       ans = ans - i
#     end
#   end

############################################################
# 初期設定
############################################################
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
sub change_variable_in_condition{
    my ($ruby_hash, $control_variable, $target_variable) = @_;

    my $caller_p = $ruby_hash->{predicate};
    # printf(STDERR "DEBUG: caller (%s)\n", $caller_p);

    if($PARSE_RUBY->is_block($ruby_hash) ||
       $PARSE_RUBY->is_method_definition($ruby_hash) ||
       $PARSE_RUBY->is_scope($ruby_hash)){
	#
	# メソッド定義，その中身，ブロック
	#

	my $index = 0;
	foreach my $sentence_hash ($PARSE_RUBY->get_all_sentences($ruby_hash)){
	    # printf STDERR "DEBUG:\t\trest(%s) in %s at %d\n", $sentence_hash->{predicate}, $caller_p, $index;
	    change_variable_in_condition($sentence_hash, $control_variable, $target_variable);
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
	change_variable_in_condition($loop, $control_var, $max_var);

    }elsif($PARSE_RUBY->is_if($ruby_hash)){
	#
	# if文
	# 
	my $if_clause = $PARSE_RUBY->get_if_clause($ruby_hash);
	if(defined($target_variable) && defined($control_variable)){
	    my ($h, $result) = 
		$PARSE_RUBY->replace_variable_into($if_clause, $control_variable, $target_variable);
	    $CHANGED = 1 if($result);
	}

	my $then_clause = $PARSE_RUBY->get_then_clause($ruby_hash);
	change_variable_in_condition($then_clause, $control_variable, $target_variable);

	#
	my $else_clause = $PARSE_RUBY->get_else_clause($ruby_hash);
	return if(!defined($else_clause));
	change_variable_in_condition($else_clause, $control_variable, $target_variable);
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

change_variable_in_condition($hash_ref);

# print "*** S-expression (change_variabele_in_loop) ***\n";
# print $PARSE_RUBY->s_reverse_parse($hash_ref);

print STDERR "\n\n*** Ruby  (change_variabele_in_for_loop_def) ***\n";
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



