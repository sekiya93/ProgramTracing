#!/usr/bin/perl -w
################################################
# 
# ruby_parser の動作テスト
#
# Time-stamp: <2013-07-08 13:39:01 sekiya>
#
# Usage: $0 ruby_program converted_program
#
################################################

use strict;
use lib '/Users/sekiya/src/eLearning/programming_skill/web/lib';
# use lib '/usr/local/plack/tracing/lib';

use ParseRuby;
use Data::Dumper;
use FileHandle;

my $PARSE_RUBY = ParseRuby->new();

# デバッグ
my $DEBUG = 0;

# 変換された場合は1
my $CHANGED = 0;

# # 2次元配列の誤解
# sub misunderstand_2D_array{
#     my ($ruby_hash) = @_;

#     # nil
#     return if(!defined($ruby_hash));

#     # シンボル又はリテラル
#     return if($PARSE_RUBY->is_literal_or_symbol($ruby_hash));
    
#     if($PARSE_RUBY->is_block($ruby_hash) ||
#        $PARSE_RUBY->is_method_definition($ruby_hash) ||
#        $PARSE_RUBY->is_scope($ruby_hash) ||
#        $PARSE_RUBY->is_for_loop($ruby_hash)){
# 	#
# 	# メソッド定義，その中身，ブロック
# 	my $index = 0;
# 	foreach my $sentence_hash ($PARSE_RUBY->get_all_sentences($ruby_hash)){
# #	    printf STDERR "DEBUG:\t\trest(%s) in %s at %d\n", $sentence_hash->{predicate}, $caller_p, $index;
# 	    # print STDERR Data::Dumper->Dump([$sentence_hash]) if($PARSE_RUBY->is_call($sentence_hash));
# 		misunderstand_2D_array($sentence_hash);
# 	 }
#      }elsif($PARSE_RUBY->is_while_loop($ruby_hash)){
# 	 #
# 	 # while
# 	 misunderstand_2D_array($ruby_hash->{rest}->[1]);
# 	 #
#      }elsif($PARSE_RUBY->is_if($ruby_hash)){
# 	 #
# 	 # if
# 	 my $if_clause = $PARSE_RUBY->get_if_clause($ruby_hash);
# 	 misunderstand_2D_array($if_clause);
# 	 # $if_clause->{rest}->[1]
# 	 # print STDERR "inequality: " . Data::Dumper->Dump([
# 	 #     $if_clause
# 	 #     # 
# 	 # 				 ]);
# 	 # if
# 	 my $then_clause = $PARSE_RUBY->get_then_clause($ruby_hash);
# 	 misunderstand_2D_array($then_clause);
# 	 #
# 	 my $else_clause = $PARSE_RUBY->get_else_clause($ruby_hash);
# 	 return if(!defined($else_clause));
# 	 misunderstand_2D_array($else_clause);

#      }elsif($PARSE_RUBY->is_assignment($ruby_hash)){
# 	 # 代入式
# 	 # - 左辺
# 	 misunderstand_2D_array($ruby_hash->{rest}->[0]);
# 	 # - 右辺
# 	 misunderstand_2D_array($ruby_hash->{rest}->[1]);

#      }elsif($PARSE_RUBY->is_array_reference($ruby_hash) &&
# 	    $PARSE_RUBY->is_array_reference($ruby_hash->{rest}->[0])){
# 	 # 2次元(以上の?)配列 -> 変換対象
# 	 my $y = $ruby_hash->{rest}->[2];
# 	 my $x = $ruby_hash->{rest}->[0]->{rest}->[2];
# 	 $ruby_hash->{rest}->[2] = $x;
# 	 $ruby_hash->{rest}->[0]->{rest}->[2] = $y;
# 	 $CHANGED = 1;

#      }elsif($PARSE_RUBY->is_call($ruby_hash)){

# 	 # print STDERR Data::Dumper->Dump([$ruby_hash]);
	 
# 	 misunderstand_2D_array($ruby_hash->{rest}->[0]);
# 	 misunderstand_2D_array($ruby_hash->{rest}->[2]);
#      }
# }

my $str = $PARSE_RUBY->generate_ruby_s_expression($ARGV[0]);

print STDERR "DEBUG: (original) $str\n";
my $hash_ref = $PARSE_RUBY->parse_s_expression($str);

# print "*** S-expression (original) ***\n";
# print $PARSE_RUBY->s_reverse_parse($hash_ref);

print STDERR "\n\n*** Ruby  (original) ***\n";
print STDERR $PARSE_RUBY->reverse_parse($hash_ref) . "\n";

# misunderstand_2D_array($hash_ref);

#  # # print "*** S-expression (misunderstand_2D_array) ***\n";
#  # # print $PARSE_RUBY->s_reverse_parse($hash_ref);

# print STDERR "\n\n*** Ruby  (misunderstand_2D_array) ***\n";
# print STDERR $PARSE_RUBY->reverse_parse($hash_ref) . "\n";

# print STDERR "result: $CHANGED\n";

# # 変換された場合のみ，変換後のコードをファイルとして出力
# my $converted_file = $ARGV[1];
# unlink($converted_file) if(-f $converted_file);
# exit 1 unless($CHANGED);

# my $fh = FileHandle->new($converted_file, O_WRONLY|O_CREAT);
# $fh->printf("%s\n", $PARSE_RUBY->reverse_parse($hash_ref));
# $fh->close();
    
