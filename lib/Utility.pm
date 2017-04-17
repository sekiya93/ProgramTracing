################################################
# 
# Utility.pm
#
# Time-stamp: <2013-08-26 14:45:00 sekiya>
#
################################################
# - ごく簡単なユーティリティのみ
# - クラスでは無く，単なるモジュールとして利用

package Utility;

use constant{
    ARRAY_START => '[',
    ARRAY_END   => ']',
};

use English;

########################################################
# 文字列と値との変換
########################################################
# 値を文字列に変換
# - 配列の処理を整理するために用いる
# - (多次元の配列には未対応)
sub value_to_string{
    my ($value) = @_;

    if(ref($value) eq 'ARRAY'){
	return '[' . join(', ', map{value_to_string($_)} @{$value}) . ']';
    }else{
	return $value;
    }
}

# 文字列を値に変換
sub string_to_value{
    my ($string) = @_;

    if($string =~ /^\[.+\]$/){
	# 配列
	return array_string_to_value($string);
    }elsif($string =~ /^(.+,.+)$/){
	# カンマ区切りのみでも配列と見做す
	return array_string_to_value("[" . $string . "]");
    }else{
	return string_to_single_value($string);
    }
}

# - 構造を持たない場合
sub string_to_single_value{
    my ($string) = @_;

    if($string =~ /^\s*([\d\-\.]+)\s*$/){
	return eval($1);
    }else{
	return $string;
    }
}

# - 配列
sub array_string_to_value{
    my ($string) = @_;

    my $tmp_string = $string;
    my @stack = ();
    while(length($tmp_string)){
	# print STDERR "DEBUG: $tmp_string\n";
	if($tmp_string =~ /^\[/){
	    push(@stack, ARRAY_START);
	}elsif($tmp_string =~ /^([^,\[\]]+)/){
	    # 通常の値
	    push(@stack, string_to_single_value($1));
	}elsif($tmp_string =~ /^\s*,\s*/){
	    # 区切り
	    # - 何もしない
	}elsif($tmp_string =~ /^\]/){
	    # 配列の終端
	    my $back = pop(@stack);
	    my @work_col = ();
	    while($back ne ARRAY_START){
		unshift(@work_col, $back);
		$back = pop(@stack);
	    }
	    push(@stack, \@work_col);
	}
	$tmp_string = $POSTMATCH;
    }
    return $stack[0];
}

########################################################
# 設問番号とCGI用の設問ラベルの変換
########################################################
# 1 -> q001
sub q_index_to_q_label{
    my ($q_index) = @_;

    return sprintf("q%03d", $q_index);
}

# q001 -> 1
sub q_label_to_q_index{
    my ($q_label) = @_;

    if($q_label =~ /^q0*([1-9]\d*)$/){
	return $1;
    }else{
	return;
    }
}

1;
