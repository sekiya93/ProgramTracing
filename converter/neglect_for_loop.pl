#!/usr/bin/perl -w
################################################
# 
# neglect_for_loop.pl
#
# Usage: ./netglect_for_loop.pl ruby_program converted_program
#
################################################
# - Ruby Program から for ループを取り除く
# - ループ部分を無視して，ループの中身だけを評価する
# -> block の中に for 文があれば，それを for 文の中身相当に置換

# ある index に文を挿入する
# - 受け手側は block

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

# ループを取り除く処理が一度でも行われれば 1
my $NEGLECT = 0;

############################################################
# 変換: ループを取り除く
############################################################
sub neglect_for_loop{
    my ($ruby_hash) = @_;

    my $caller_p = $ruby_hash->{predicate};
    printf(STDERR "DEBUG: caller (%s)\n", $caller_p) if($DEBUG);

    if($PARSE_RUBY->is_block($ruby_hash) ||
       $PARSE_RUBY->is_method_definition($ruby_hash) ||
       $PARSE_RUBY->is_scope($ruby_hash)){
	#
	# メソッド定義やブロックなどの場合
	# - 複数の命令文で構成される
	my $index = 0;
	foreach my $sentence_hash ($PARSE_RUBY->get_all_sentences($ruby_hash)){
	    # printf STDERR "DEBUG:\t\trest(%s) in %s at %d\n", $sentence_hash->{predicate}, $caller_p, $index;
	    # 中身に対して，更に処理を実行
	    neglect_for_loop($sentence_hash);
	    #
	    # for ループの場合
	    if($PARSE_RUBY->is_for_loop($sentence_hash)){
		# print STDERR "DEBUG: is_for_loop! at $index\n";
		my $contents = $PARSE_RUBY->get_contents_of_for_loop($sentence_hash);
		# for ループを含む上位構造から，for ループを取り除き，
		# for ループの中身と置き換える
		$PARSE_RUBY->replace_sentence_at($ruby_hash, $contents, $index);
		$NEGLECT = 1;
	    }
	    $index = $index + 1;
	}
    }elsif($PARSE_RUBY->is_for_loop($ruby_hash)){
	#
	# for
	my $loop = $PARSE_RUBY->get_contents_of_for_loop($ruby_hash);
	neglect_for_loop($loop);
	return if(!$PARSE_RUBY->is_for_loop($loop));
	my $contents = $PARSE_RUBY->get_contents_of_for_loop($loop);
	my $index = $PARSE_RUBY->index_of_contents_of_for_loop();
	$PARSE_RUBY->replace_sentence_at($ruby_hash, $contents, $index);
	$NEGLECT = 1;
    }elsif($PARSE_RUBY->is_if($ruby_hash)){
	#
	# if
	my $then_clause = $PARSE_RUBY->get_then_clause($ruby_hash);
	neglect_for_loop($then_clause);

	if($PARSE_RUBY->is_for_loop($then_clause)){
	    my $contents = $PARSE_RUBY->get_contents_of_for_loop($then_clause);
	    my $index = $PARSE_RUBY->index_of_then_clause();
	    $PARSE_RUBY->replace_sentence_at($ruby_hash, $contents, $index);
	    $NEGLECT = 1;
	}
	# else が在る場合 
	my $else_clause = $PARSE_RUBY->get_else_clause($ruby_hash);
	return if(!defined($else_clause));

	# print STDERR Data::Dumper->Dump([$ruby_hash]);

	neglect_for_loop($else_clause);

	if($PARSE_RUBY->is_for_loop($else_clause)){
	    my $contents = $PARSE_RUBY->get_contents_of_for_loop($else_clause);
	    my $index = $PARSE_RUBY->index_of_else_clause();
	    $PARSE_RUBY->replace_sentence_at($ruby_hash, $contents, $index);
	    $NEGLECT = 1;
	}
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

# 変換処理実行
neglect_for_loop($hash_ref);

# print "*** S-expression (neglect_for_loop) ***\n";
# print $PARSE_RUBY->s_reverse_parse($hash_ref);

print STDERR "\n\n*** Ruby  (neglect_for_loop) ***\n";
print STDERR $PARSE_RUBY->reverse_parse($hash_ref) . "\n";

if($NEGLECT){
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

