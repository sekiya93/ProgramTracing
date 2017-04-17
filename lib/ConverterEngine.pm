################################################
# 
# ConverterEngine.pm
#
# Time-stamp: <2013-08-08 18:16:24 sekiya>
#
################################################
# - 当初は正しいコードから誤答パターンに従うコードを
#   生成するためのモジュールと想定
# - ユーティリティのような機能も付加

package ConverterEngine;

use constant{
    CONFIG_DIR        => 'conf',
    #
    QUEST_TYPE_INVERSE              => "inverse_trace",
    QUEST_TYPE_TRACE                => "trace",
    QUEST_TYPE_TRACE_MORE_THAN_ONE  => "trace_more_than_one",
    QUEST_TYPE_OUTPUT               => "trace_output",
    QUEST_TYPE_OUTPUT_MORE_THAN_ONE => "trace_output_more_than_one",
};

use Config::Simple;
use Text::CSV;
use POSIX;

my %CONFIG;
my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

use ParseRuby;
use Utility;

our $PARSE_RUBY = ParseRuby->new();

our %CONVERTER_DATA = ();
our $READ_CONVERTER_FILE = 0;

########################################################
# 初期化
########################################################
sub new{
    my $type = shift;
    my $self = {};
    bless $self, $type;
    return $self;
}

########################################################
# 誤答パターンの読み込み
########################################################
sub read_converter_file{
    my ($self, $file) = @_;

    if(!defined($file)){
	# デフォルトの変換器ファイル

	$file = sprintf("%s/converter.dat", CONFIG_DIR);
	# mtime の比較
	my @col = stat($file);
	return \%CONVERTER_DATA if($col[9] < $READ_CONVERTER_FILE);
    }

    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    open(my $io, "<", $file) or die "$file: $!";

    $READ_CONVERTER_FILE = time();

    while (my $row = $csv->getline($io)) {
	next if($row->[0] =~ /^\#/); # コメント行をスキップ

	my %each_data = ();

	$each_data{label}       = $row->[0];
	$each_data{script}      = $row->[1];
	$each_data{description} = $row->[2];

	$CONVERTER_DATA{$each_data{label}} = \%each_data;
    }

    $csv->eof() or $csv->error_diag();
    close($io);

    return \%CONVERTER_DATA;
}

########################################################
# 誤答パターンの読み込み
########################################################
sub get_converter_data{
    my ($self) = @_;

    return $self->read_converter_file();
}

########################################################
# コード実行
########################################################
# ruby のコードを実行する
# - $ruby_code は絶対パスで指定するか
# sub evaluate_ruby_code{
#     my ($self, $ruby_code, $input) = @_;

#     my $method_name = $self->_extract_method_name($ruby_code);

#     my $file = $CONFIG{TMP_DIR} . '/make_answer_' . $$ . '.rb';
#     unlink($file) if(-f $file);
#     # print STDERR "DEBUG: file($file), method_name($method_name)\n";

#     my $input_fh = FileHandle->new($ruby_code, O_RDONLY);
#     die "Cannot open $ruby_code." if(!defined($input_fh));
#     my $output_fh = FileHandle->new($file, O_WRONLY|O_CREAT);
#     die "Cannot open $file." if(!defined($output_fh));

#     while(my $line = $input_fh->getline()){
# 	$output_fh->print($line);
#     }
 
#     my $value_string = Utility::value_to_string($input);
#     $output_fh->printf("\np %s(%s)\n\n", $method_name, $value_string);
#     $output_fh->close();
    
#     my $command = sprintf("%s %s|", $CONFIG{RUBY}, $file);
#     # print STDERR "DEBUG: $command ($ruby_code)\n";
#     open(COMMAND, $command) or die "Cannot execute $command.";
#     my $answer = <COMMAND>;
#     close(COMMAND);
#     if(defined($answer)){
# 	# Fri Apr 26 19:13:58 2013
# 	return Utility::string_to_value($answer);
#     }else{
# 	return $CONFIG{NO_ANSWER};
#     }
# }

# ruby のコードを実行する
# - $ruby_code は絶対パスで指定するか
sub evaluate_ruby_code{
    my ($self, $ruby_code, $input, $quest_type) = @_;

    my $method_name = $self->_extract_method_name($ruby_code);

    # 実行用の一時ファイルの生成
    my $file = $CONFIG{TMP_DIR} . '/make_answer_' . $$ . '.rb';
    unlink($file) if(-f $file);

    my $input_fh = FileHandle->new($ruby_code, O_RDONLY);
    die "Cannot open $ruby_code." if(!defined($input_fh));
    my $output_fh = FileHandle->new($file, O_WRONLY|O_CREAT);
    die "Cannot open $file." if(!defined($output_fh));

    while(my $line = $input_fh->getline()){
	$output_fh->print($line);
    }

    # 入力値の扱い
    my $value_string;
    if($quest_type eq QUEST_TYPE_TRACE_MORE_THAN_ONE ||
       $quest_type eq QUEST_TYPE_OUTPUT_MORE_THAN_ONE){
	# - 複数の引数を並べる
	$value_string = join(", ", map{Utility::value_to_string($_)} @{$input});
    }else{
	# - 一個の引数
	$value_string = Utility::value_to_string($input);
    }

    if($quest_type eq QUEST_TYPE_TRACE ||
       $quest_type eq QUEST_TYPE_TRACE_MORE_THAN_ONE){
	# - 戻り値を問う場合
	$output_fh->printf("\np %s(%s)\n\n", $method_name, $value_string);
    }else{
	# - 単に実行する時
	$output_fh->printf("\n%s(%s)\n\n", $method_name, $value_string);
    }
    $output_fh->close();
    
    my $command = sprintf("%s %s|", $CONFIG{RUBY}, $file);
    my @answer_col = ();
    open(COMMAND, $command) or die "Cannot execute $command.";
    while(my $answer = <COMMAND>){
	chomp($answer);
	if(defined($answer)){
	    # Fri Apr 26 19:13:58 2013
	    push(@answer_col, Utility::string_to_value($answer));
	}else{
	    push(@answer_col, $CONFIG{NO_ANSWER});
	}
    }
    close(COMMAND);

    if(scalar(@answer_col) == 1){
	return pop(@answer_col);
    }else{
	return \@answer_col;
    }
}

######################################################
# 正答及び誤答データを生成 
######################################################
# - 当面は変換後のコードを作っておく
# - $answer_item_hash_ref = {index => 13, source => 'a7.rb', ...}
sub evaluate_answer_item{
    my ($self, $answer_item_ref, $converter_data_ref) = @_;

    # 正答を求める
    $answer_item_ref->{answer} = $CONFIG{NO_ANSWER}; # 現在の値をリセット

    # inverse trace は特別な処理を行う
    if($answer_item_ref->{type} eq QUEST_TYPE_INVERSE){
	return $self->evaluate_answer_item_of_inverse_trace($answer_item_ref);
    }

    my $original_code = sprintf("%s/%s", $CONFIG{RUBY_CODE_DIR}, $answer_item_ref->{source});

    my $answer = 
	$self->evaluate_ruby_code($original_code, 
				  $answer_item_ref->{input},
				  $answer_item_ref->{type});
    $answer_item_ref->{answer} = $answer;

    # debug (Mon Sep 17 11:22:44 2012)
    # return $answer_item_ref;

    # 誤答
    if(!defined($converter_data_ref)){
	$converter_data_ref = $self->get_converter_data();
    }

    foreach my $label (keys(%{$converter_data_ref})){
	# 誤答のみを扱う
	next if($label =~ /^(unknown|no_answer|answer)$/);

	$answer_item_ref->{$label} = $CONFIG{NO_ANSWER};
	my $converted_code = 
	    sprintf("%s/%s/%s", $CONFIG{CONVERTED_DIR}, $answer_item_ref->{source}, $label);
	next if(! -f $converted_code);
	my $wrong_answer = $self->evaluate_ruby_code($converted_code, $answer_item_ref->{input});
	if($self->_compare_answers($answer, $wrong_answer)){
	    $answer_item_ref->{$label} = $CONFIG{NO_ANSWER};
	}else{
	    $answer_item_ref->{$label} = $wrong_answer;
	}
    }

    return $answer_item_ref;
}

# Inverse Trace の評価専用
sub evaluate_answer_item_of_inverse_trace{
    my ($self, $answer_item_ref) = @_;

    # 正答を求める
    $answer_item_ref->{answer} = $CONFIG{NO_ANSWER}; # 現在の値をリセット
    my $original_code = sprintf("%s/%s", $CONFIG{RUBY_CODE_DIR}, $answer_item_ref->{source});

    my @col = ();
    for(my $input = $CONFIG{MIN_FOR_INVERSE_TRACE}; $input <= $CONFIG{MAX_FOR_INVERSE_TRACE}; $input++){
	my $answer = $self->evaluate_ruby_code($original_code, $input);
	printf STDERR "DEBUG (input:%d, answer:%d)\n", $input, $answer;
	if(abs($answer - $answer_item_ref->{input}) <= $CONFIG{PERMISSIBLE_ERROR_FOR_INVERSE_TRACE}){
	    push(@col, $input);
	}
    }

    $answer_item_ref->{answer} = \@col;

    return $answer_item_ref;
}

########################################################
# 正誤判定
########################################################
sub set_result_of_exam_response{
    my ($self, $exam_response, $exam_answer_data_col_ref, $converter_data_ref) = @_;

    my @error_label_col;
    if(defined($converter_data_ref)){
	@error_label_col = keys(%{$converter_data_ref});
    }else{
	@error_label_col = keys(%{$self->get_converter_data()});
    }

    # 設問ごとの判定結果
    my %result_data = ();
    # 正解したか否か
    my %correct_data = ();

    # 設問毎に誤答パターンと一致するか確認する
    foreach my $exam_answer_data (@{$exam_answer_data_col_ref}){
	my $q_index = $exam_answer_data->{index};
	my $each_response = $exam_response->get_response($exam_answer_data->{index});
	# printf(STDERR "q_label:%s\n", $q_label);
	my $user_answer = $each_response->{user_answer};

	$each_response->{result}      = 0;	
	$each_response->{error_label} = [];

	# 当該設問が無回答
	next if($user_answer eq $CONFIG{NO_ANSWER});

	# 誤答(+正答)毎に判定
	foreach my $error_label (@error_label_col){
	    my $incorrect_answer = $exam_answer_data->{$error_label};
	    
	    # 当該設問に定義されない誤答パターンが候補として，
	    # 表示されることを防ぐ (Mon Apr  8 16:54:51 2013)
	    next if(!defined($incorrect_answer));
	    
	    next if($error_label eq 'unknown' || $error_label eq 'no_answer');

	    # 誤答パターンが無い
	    next if($incorrect_answer eq $CONFIG{NO_ANSWER});

	    print STDERR "compare: " . Data::Dumper->Dump([$user_answer, $incorrect_answer]) if($error_label eq 'answer');
	    if($self->_compare_answers($user_answer, $incorrect_answer)){
		push(@{$each_response->{error_label}}, $error_label);
		$each_response->{result} = 1 if($error_label eq $CONFIG{ANSWER_LABEL});
	    }
	}

	# 判定結果を登録
	$exam_response->set_each_response($each_response);
    }
}

########################################################
# ユーティリティ
########################################################
# ruby のコードからメソッド名を取り出す
sub _extract_method_name{
    my ($self, $ruby_code) = @_;

    my $str = $PARSE_RUBY->generate_ruby_s_expression($ruby_code);
    # print STDERR "DEBUG: (original) $str\n";
    my $hash_ref = $PARSE_RUBY->parse_s_expression($str);
    die "Not method." if(!$PARSE_RUBY->is_method_definition($hash_ref));

    return $PARSE_RUBY->get_method_name($hash_ref);
}

# 比較
# - 配列対応が必要 (Fri Sep 14 16:58:32 2012)
sub _compare_answers{
    my ($self, $answer1, $answer2) = @_;

    # 定義されていなければ 0
    return 0 if(!defined($answer1) || !defined($answer2));

    if(ref($answer1) eq 'ARRAY' && ref($answer2) eq 'ARRAY'){
	my $size1 = scalar(@{$answer1});
	return 0 if(scalar(@{$answer2}) != $size1);

	my $c = 0;
	while($c < $size1){
	    return 0 if($answer1->[$c] != $answer2->[$c]);
	    $c++;
	}
	return 1;
    }elsif(ref($answer1) eq 'ARRAY' && scalar(@{$answer1}) == 1){
	# $answer1 のみ配列の場合
	return $self->_compare_answers($answer1->[0], $answer2);
    }elsif(ref($answer2) eq 'ARRAY' && scalar(@{$answer2}) == 1){
	# $answer1 のみ配列の場合
	return $self->_compare_answers($answer1, $answer2->[0]);
    }else{
	return ($answer1 == $answer2);
    }
}

# 値を文字列に変換
# - 配列の処理を整理するために用いる
# sub value_to_string{
#     my ($value) = @_;

#     if(ref($value) eq 'ARRAY'){
# 	return '[' . join(', ', @{$value}) . ']';
#     }else{
# 	return $value;
#     }
# }

# # 文字列を値変換
# # - 配列の処理を整理するために用いる
# sub string_to_value{
#     my ($self, $string) = @_;

#     $string =~ s/\s//g;
#     if($string =~ /^\[(.+)\]$/){
# 	# 配列
# 	$string = $1;
# 	my @col = ();
#  	map{push(@col, $self->string_to_value($_))} split(/,/, $string);
# 	return \@col;
#     }elsif($string =~ /([\d\-\.]+)/){
# 	# 数値の扱い
# 	return eval($1);
#     }else{
# 	return $string;
#     }
# }

1;
