#!/usr/bin/perl -w
################################################
# 
# regard_as_array.pl
#
# Usage: ./regard_as_array.pl ruby_program converted_program
#
################################################
# - 返り値となる変数を配列と見做す
# - (コード変換では表現し辛いか...)
# - ループの場合に顕著となる
# -- ループの中身では，更に制御変数に置換する
# - 返り値の取扱いに注意が必要か
# - 返り値となる変数は ans と決め打ち
# (例)
# def a3(a)
#   ans = 0
#   for i in 1..a
#     ans = ans + a
#   end
#   p ans
# end
# ->
# def a3(a)
#   ans = []
#   for i in 1..a
#     ans.push(i)
#   end
#   p ans
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
my $DEBUG = 1;

# 変換処理が行われれば
my $CONVERTED = 0;

# ループが在る場合のみ
my $HAS_FOR_LOOP = 0; 

############################################################
# 変換後の代入式
############################################################
# 配列初期化
sub generate_array_initial{
    my ($sentence_hash) = @_;

    my $left_term    = $sentence_hash->{rest}->[0];
    my $string       = $PARSE_RUBY->reverse_parse($left_term);
    
    $string .= ' = ';
    my $value        = $sentence_hash->{rest}->[1]->{rest}->[0]->{literal};
    if(defined($value) && $value != 0){
	$string .= sprintf("[%s]", $value);
    }else{
	$string .= '[]';
    }

    return $PARSE_RUBY->parse_ruby_source($string);
}

# push に置き換えるか
sub can_regard_push{
    my ($sentence_hash) = @_;

    # 左辺
    my $left_term    = $sentence_hash->{rest}->[0];

    # 少なくとも :call であること
    return 0 if($sentence_hash->{rest}->[1]->{predicate} ne ':call');
    my $call_terms_ref = $sentence_hash->{rest}->[1]->{rest};
    
    # 左辺と同じ文字が用いられている
    return 0 if($left_term->{symbol} ne $call_terms_ref->[0]->{rest}->[0]->{symbol});

    # debug
    # print STDERR 'can_regard_push:' . Data::Dumper->Dump([$sentence_hash]);

    return 1;
}

# 配列への push
sub generate_array_push{
    my ($sentence_hash) = @_;

    my $left_term    = $sentence_hash->{rest}->[0];
    my $string       = $PARSE_RUBY->reverse_parse($left_term);
    
    $string .= '.push(';

    my $operator    = $sentence_hash->{rest}->[1]->{rest}->[1];
    my $operator_string = $PARSE_RUBY->reverse_parse($operator);
    if($operator_string ne '+'){
	$string .= $operator_string;
    }
    my $target_data = $sentence_hash->{rest}->[1]->{rest}->[2];
    $string .= $PARSE_RUBY->reverse_parse($target_data);
    $string .= ')';

    printf(STDERR "generate_array_push: %s\n", $string);

    if($DEBUG){
	printf(STDERR "DEBUG: %s\n", $PARSE_RUBY->generate_ruby_s_expression_from_string($string));
    }
    return $PARSE_RUBY->parse_ruby_source($string);
}

############################################################
# 変換: 配列と見做す
############################################################
sub regard_child_sentence_as_array{
    my ($child, $parent, $index_of_child) = @_;

    # 代入式でない場合
    return 0 if(!$PARSE_RUBY->is_assignment($child));

    my $regarded;
    if($child->{rest}->[1]->{predicate} eq ':lit'){
	$regarded = generate_array_initial($child);
	return 0 if(!defined($regarded));
	# 置換
	$PARSE_RUBY->replace_sentence_at($parent,
					 $regarded, 
					 $index_of_child);
	
    }elsif(can_regard_push($child)){
	# return 0 if(!$PARSE_RUBY->is_for_loop($parent));
	$regarded = generate_array_push($child);

	return 0 if(!defined($regarded));
	# 置換
	$PARSE_RUBY->replace_sentence_at($parent,
					 $regarded, 
					 $index_of_child);
	$CONVERTED = 1;
    }

    return 1;
}

sub regard_as_array{
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
	    regard_as_array($sentence_hash);
	    #
	    regard_child_sentence_as_array($sentence_hash,
					   $ruby_hash, 
					   $index);
	    $index = $index + 1;
	}
    }elsif($PARSE_RUBY->is_for_loop($ruby_hash)){
	$HAS_FOR_LOOP = 1;
	#
	# for

	# 制御変数
	my $control_var = $PARSE_RUBY->get_control_variable_of_for_loop($ruby_hash);
	# 最大値(に相当する変数)
	# - 最大値が変数として与えられていることを前提とする
	my $max_var     = $PARSE_RUBY->get_max_range_of_for_loop($ruby_hash);

	# ループの中身
	my $loop = $PARSE_RUBY->get_contents_of_for_loop($ruby_hash);
	regard_as_array($loop);

	# 変数の変換処理も行う
	my ($h, $result) = $PARSE_RUBY->replace_variable_into($loop, $max_var, $control_var);

	my $index = $PARSE_RUBY->index_of_contents_of_for_loop();
	regard_child_sentence_as_array($loop,
				       $ruby_hash, 
				       $index);
    }elsif($PARSE_RUBY->is_if($ruby_hash)){
	#
	# if
	my $then_clause = $PARSE_RUBY->get_then_clause($ruby_hash);
	regard_as_array($then_clause);

	my $index = $PARSE_RUBY->index_of_then_clause();
	regard_child_sentence_as_array($then_clause,
				       $ruby_hash, 
				       $index);

	# else が在る場合 
	my $else_clause = $PARSE_RUBY->get_else_clause($ruby_hash);
	return if(!defined($else_clause));

	regard_as_array($else_clause);

	$index = $PARSE_RUBY->index_of_else_clause();
	regard_child_sentence_as_array($else_clause,
				       $ruby_hash, 
				       $index);
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
regard_as_array($hash_ref);

# print "*** S-expression (neglect_for_loop) ***\n";
# print $PARSE_RUBY->s_reverse_parse($hash_ref);

print STDERR "\n\n*** Ruby  (regard_as_array) ***\n";
print STDERR $PARSE_RUBY->reverse_parse($hash_ref) . "\n";

if($CONVERTED && $HAS_FOR_LOOP){
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

