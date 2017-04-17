#!/usr/bin/perl -w
################################################
# 
# 不等号のみの条件式に，等号を追加して解釈
#
# Time-stamp: <2013-07-08 15:24:47 sekiya>
#
# Usage: $0 ruby_program converted_program
#
# (例)
# if i > 3 then
#   ans = ans + a
# end
# -> 
# if i >= 3 then
#   ans = ans + a
# end 
#
################################################

use strict;
# use lib '/Users/sekiya/src/eLearning/programming_skill/web/lib';
#use lib '/usr/local/plack/tracing/lib';
use lib './lib';

use ParseRuby;
use Data::Dumper;
use FileHandle;

my $PARSE_RUBY = ParseRuby->new();

# デバッグ
my $DEBUG = 0;

# 変換された場合は1
my $CHANGED = 0;

# ループ内の変数を，for ループの制御変数に置き換える
# - 二重ループは... 取りあえず考えないか
sub add_equality_to_inequality{
    my ($ruby_hash) = @_;

    my $caller_p = $ruby_hash->{predicate};

    # printf(STDERR "DEBUG: caller (%s)\n", $caller_p);

    if($PARSE_RUBY->is_block($ruby_hash) ||
       $PARSE_RUBY->is_method_definition($ruby_hash) ||
       $PARSE_RUBY->is_scope($ruby_hash) ||
       $PARSE_RUBY->is_for_loop($ruby_hash)){
	#
	# メソッド定義，その中身，ブロック
	my $index = 0;
	foreach my $sentence_hash ($PARSE_RUBY->get_all_sentences($ruby_hash)){
#	    printf STDERR "DEBUG:\t\trest(%s) in %s at %d\n", $sentence_hash->{predicate}, $caller_p, $index;
	     add_equality_to_inequality($sentence_hash);
	 }
     }elsif($PARSE_RUBY->is_while_loop($ruby_hash)){
	 #
	 # while
	 add_equality_to_inequality($ruby_hash->{rest}->[1]);
	 #
     }elsif($PARSE_RUBY->is_if($ruby_hash)){
	 #
	 # if
	 my $if_clause = $PARSE_RUBY->get_if_clause($ruby_hash);
	 add_equality_to_inequality($if_clause);
	 # 
	 my $then_clause = $PARSE_RUBY->get_then_clause($ruby_hash);
	 add_equality_to_inequality($then_clause);
	 #
	 my $else_clause = $PARSE_RUBY->get_else_clause($ruby_hash);
	 #
	 return if(!defined($else_clause));
	 #
	 add_equality_to_inequality($else_clause);
     }elsif($PARSE_RUBY->is_call($ruby_hash)){
	 #
	 # 比較条件式
	 # - 不等号を入れ替える
	 my $sign_hash = $ruby_hash->{rest}->[1];
	 if($sign_hash->{symbol} eq '>'){
	     $sign_hash->{symbol} = '>=';
	     $CHANGED = 1;
	 }elsif($sign_hash->{symbol} eq '<'){
	     $sign_hash->{symbol} = '<=';
	     $CHANGED = 1;
	 }
     }
}

my $str = $PARSE_RUBY->generate_ruby_s_expression($ARGV[0]);

print STDERR "DEBUG: (original) $str\n";
my $hash_ref = $PARSE_RUBY->parse_s_expression($str);

# print "*** S-expression (original) ***\n";
# print $PARSE_RUBY->s_reverse_parse($hash_ref);

print STDERR "\n\n*** Ruby  (original) ***\n";
print STDERR $PARSE_RUBY->reverse_parse($hash_ref) . "\n";

add_equality_to_inequality($hash_ref);

 # # print "*** S-expression (add_equality_to_inequality) ***\n";
 # # print $PARSE_RUBY->s_reverse_parse($hash_ref);

print STDERR "\n\n*** Ruby  (add_equality_to_inequality) ***\n";
print STDERR $PARSE_RUBY->reverse_parse($hash_ref) . "\n";

print STDERR "result: $CHANGED\n";

# 変換された場合のみ，変換後のコードをファイルとして出力
my $converted_file = $ARGV[1];
unlink($converted_file) if(-f $converted_file);
exit 1 unless($CHANGED);

my $fh = FileHandle->new($converted_file, O_WRONLY|O_CREAT);
$fh->printf("%s\n", $PARSE_RUBY->reverse_parse($hash_ref));
$fh->close();
    
