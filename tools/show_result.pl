#!/usr/bin/perl -w
############################################################
#
# データの集計用スクリプト (2012-05-01)
#
# Time-stamp: <2013-08-08 18:28:27 sekiya>
#
# - いずれは Web 化
#
############################################################
use strict;
use warnings;
# ローカルのモジュールを利用するため，ライブラリのパスを
# 明示的に設定
use lib '/usr/local/plack/tracing/lib';

# config ファイルを指定するスマートな方法は無いものか
use constant{
    CONFIG_DIR => '/usr/local/plack/tracing/conf',
    #
    TIME_ZONE  => 'Asia/Tokyo',
    #
    CORRECT_ANSWER_LABEL => 'answer',
};

use FileHandle;
use Text::CSV;
use DateTime;
use POSIX;
use Data::Dumper;
use Config::Simple;

my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
my %CONFIG;
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

# use CFIVE::CfiveUser;
use Exam::File;
use ExamResponse::File;
use ConverterEngine;
my $CONVERTER = ConverterEngine->new();

my $DEBUG = 2;

my ($DATE_SINCE, $DATE_TILL, $exam_id, $CSV, $UT, $EVAL, $ANSWER_FILE, $CONVERTER_DATA_FILE);
use Getopt::Long qw(:config auto_help);
GetOptions(
    "since=s"       => \$DATE_SINCE,
    "till=s"        => \$DATE_TILL,
    "exam_id=s"     => \$exam_id,
    "csv"           => \$CSV,
    "ut"            => \$UT,
    "eval"          => \$EVAL, # 再度誤答パターンを評価
    "answer_file=s" => \$ANSWER_FILE,
    "converter=s"   => \$CONVERTER_DATA_FILE,
    ) or exit 1;
die "No exam ID!" if(!defined($exam_id));

=head1 SYNOPSIS

    ./show_answer.pl [--since YYYY-mm-dd] [--till YYYY-mm-dd] --exam_id exam_id

=cut


####################################### 
# 日付処理
#######################################
sub convert_since_and_till{

    my @result = ();
    if(defined($DATE_SINCE) && $DATE_SINCE =~ /(^\d{4})\-(\d{2})\-(\d{2})/){
	$result[0] = DateTime->new(
		 year       => $1,
		 month      => $2,
		 day        => $3,
		 hour       => 0,
		 minute     => 0,
		 second     => 0,
		 time_zone  => TIME_ZONE,
	    );

    }

    if(defined($DATE_TILL) && $DATE_TILL =~ /(^\d{4})\-(\d{2})\-(\d{2})/){
	$result[1] = DateTime->new(
	    year       => $1,
	    month      => $2,
	    day        => $3,
	    hour       => 0,
	    minute     => 0,
	    second     => 0,
	    time_zone  => TIME_ZONE,
         );
    }

    return @result;
}

####################################### 
# 試験問題
#######################################
# 試験問題一覧の取得
# # id,name,registered,modified,description
# sub read_exam_list{ 

#     my $file = sprintf("%s/exam_list.dat", $CONFIG{EXAM_DIR});
    
#     my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
#     open(my $io, "<", $file) or die "$file: $!";

#     my %exam_list_hash = ();

#     while (my $row = $csv->getline ($io)) {
# 	# コメント行
# 	next if($row->[0] =~ /^#/);

# 	my $exam_data = {
# 	    id           => $row->[0],
# 	    name         => $row->[1],
# 	    registered   => $row->[2],
# 	    modified     => $row->[3],
# 	    description  => $row->[4],
# 	};

# 	$exam_list_hash{$exam_data->{id}} = $exam_data;
#     }
#     $csv->eof() or $csv->error_diag();

#     close($io);

#     return \%exam_list_hash;
# }

############################################################
# 正答ならびに誤答データの読み込み
#
# index,source,input,answer,,NEGLECT_FOR_LOOP,...
# 1,a1.rb,3,-3,-
# 2,a1.rb,4,5,-
# ...
############################################################
# 設問番号とCGI用の設問ラベルの変換
# - 1ヶ所にまとめておく
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

# 設問毎の解答・誤答のデータ
sub read_exam_answer_file{
    my ($exam_id) = @_;

    my $file = sprintf("%s/%s/answer.csv", $CONFIG{EXAM_DIR}, $exam_id);

    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    open(my $io, "<", $file) or die "$file: $!";

    # 1行目は列ラベル
    my $row = $csv->getline($io);
    my @answer_data_column_names = @{$row};

    # 2行目以降は設問毎の正答ならびに誤答データ
    my @answer_data_col = ();
    my $counter = 1;
    while (my $row = $csv->getline ($io)) {
	my %answer_data = ();
	for(my $i = 0; $i < scalar(@answer_data_column_names); $i++){
	    # ラベル (NEGLECT_FOR_LOOP, ..など)
	    my $label = $answer_data_column_names[$i];

	    # 正答又は誤答
	    my $answer = $row->[$i];
	    if($answer =~ /\[/){
		# 配列
		$answer =~ s/[^\d,\-\.]//g;
		my @col = split(/,/, $answer);
		$answer_data{$label} = \@col;
	    }else{
		# 通常の数値のみの答え
		$answer_data{$label} = $answer;
	    }
	}
	$counter++;
	push(@answer_data_col, \%answer_data);
    }
    $csv->eof() or $csv->error_diag();
    close($io);

    return (\@answer_data_column_names, \@answer_data_col);
}

########################################################
# 集計結果
# - 正答率
########################################################
sub get_result{
    my ($user_answer_data_col_ref) = @_;

    # 全学生の総計
    my %total_result_hash = ();
    $total_result_hash{unknown}   = 0; # 不明
    $total_result_hash{no_answer} = 0; # 解答無し

    # 学生毎の誤答パターンの処理
    foreach my $user_answer_data (@{$user_answer_data_col_ref}){

	# print STDERR 'unknown DEBUG: ' . $user_answer_data->{userid} . ' ';
	# print STDERR 'NO_ANSWER DEBUG: ' . $user_answer_data->{userid} . ' ';

	# 設問毎に誤答パターンと一致するか確認する
	my %result_hash = (); # 個々の学生ごとの小計
	$result_hash{unknown}   = 0;
	$result_hash{no_answer} = 0;

	foreach my $answer (@{$user_answer_data->{answers}}){
	    if($answer->{answer} eq $CONFIG{NO_ANSWER}){
		$result_hash{no_answer} += 1;
		# print STDERR $answer->{index} . ' ';
	    }else{
		my @label_col = @{$answer->{error_label}};
		if(scalar(@label_col) < 1){
		    $result_hash{unknown} += 1;
		    # print STDERR $answer->{index} . ' ';
		    store_unknown_data($user_answer_data->{userid},
				       $answer->{index},
				       $answer->{answer});
		}else{
		    map{$result_hash{$_} += 1} @label_col;
		}
	    }
	}

	# print STDERR "\n";
	# if($result_hash{unknown} > 0){
	#     print STDERR Data::Dumper->Dump([$user_answer_data]);
	# }

	$user_answer_data->{result} = \%result_hash;

	# 全学生の総計に，当該学生の集計結果を加える
	map {$total_result_hash{$_} += $result_hash{$_}} keys(%result_hash);
    }

    return \%total_result_hash;
}

#######################################
# 解答
#######################################

# ファイルに保存して有った個々の学生の解答結果を読込む

# $answer_data->{exam_id}
#            ->{userid}
#            ->{realm}
#            ->{fullname}
#            ->{date}
#            ->{answers} = []
#            ->{total_score} 
# $answer->{index}
#        ->{answer}
#        ->{result}
#        ->{error_label}
sub read_answer_file{
    my ($file) = @_;

    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    open(my $io, "<", $file) or die "$file: $!";

    my %answer_data = ();
    # 1行目は，コメント行として基本情報を書いておく
    my $first_line = $csv->getline($io);
    foreach my $data (@{$first_line}){
	$data =~ s/^[\#\s]+//;
	next if($data !~ /^(\w+):\s*(\S.+)/);
	$answer_data{$1} = $2;
	printf(STDERR "DEBUG: key: %s, value: %s\n", $1, $2) if($DEBUG);
    }

    # 総得点を求める
    $answer_data{total_score} = 0;

    my @col = ();
    while (my $row = $csv->getline($io)) {
	next if($row->[0] =~ /^\#/); # コメント行をスキップ
	my %each_data = ();
	# 設問
	$each_data{index} = $row->[0];
	# 解答
	if($row->[1] =~ /,/){
	    my @value_col = split(/,/, $row->[1]);
	    $each_data{answer} = \@value_col;
	}else{
	    $each_data{answer} = $row->[1];
	}
	# 結果
	$each_data{result} = $row->[2];
	# 誤答パターン
	my @pattern_col = split(/,/, $row->[3]);
	foreach my $pattern (@pattern_col){
	    $answer_data{total_score}++ if($pattern eq CORRECT_ANSWER_LABEL);
	}
	$each_data{error_label} = \@pattern_col;

	printf(STDERR "DEBUG: %s\n", join(", ", @{$row})) if($DEBUG > 1);

	push(@col, \%each_data);
    }

    $csv->eof() or $csv->error_diag();
    close($io);
    $answer_data{answers} = \@col;

    printf STDERR "DEBUG: total_score %d\n",  $answer_data{total_score} ;

    return \%answer_data;
}

sub get_answer_files{
    my ($exam_id, $range_ref) = @_;

    my $answer_dir = sprintf("%s/%s", $CONFIG{ANSWER_DIR}, $exam_id);
    die "Cannot open the directory $answer_dir." if(!-d $answer_dir);

    # 拡張子が dat であることが前提
    my @tmp_files = glob("$answer_dir/*.dat");

    # 当面は since のみ
    if(!defined($range_ref->[0]) && !defined($range_ref->[1])){
	return @tmp_files;
    }
    my ($since, $till) = @{$range_ref};

    my @answer = ();
    foreach my $file (@tmp_files){
	next if($file !~ /(\d{4})\-(\d{2})\-(\d{2})_(\d{2})(\d{2})_(\d{2})\./);
	my $file_dt = DateTime->new(
             year       => $1,
             month      => $2,
             day        => $3,
             hour       => $4,
             minute     => $5,
             second     => $6,
             time_zone  => TIME_ZONE,
	    );
	next if(defined($since) && DateTime->compare($file_dt, $since) < 0);
	next if(defined($till)  && DateTime->compare($file_dt, $till)  > 0);
	push(@answer, $file);
    }

    return @answer;
}

# 変換器の読み込み
sub read_converter_file{

    my $file = sprintf("%s/converter.dat", CONFIG_DIR);
    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    open(my $io, "<", $file) or die "$file: $!";

    my %converter_data = ();
    while (my $row = $csv->getline($io)) {
	next if($row->[0] =~ /^\#/); # コメント行をスキップ

	my %each_data = ();

	$each_data{label}       = $row->[0];
	$each_data{script}      = $row->[1];
	$each_data{description} = $row->[2];

	printf(STDERR "DEBUG: %s\t%s\t%s\n", 
	       $each_data{label},
	       $each_data{script},
	       $each_data{description}) if($DEBUG);

	$converter_data{$each_data{label}} = \%each_data;
    }

    $csv->eof() or $csv->error_diag();
    close($io);

    return \%converter_data;
}


# 再評価
# - answer.csv が更新された場合を考慮
# - 設問がどの時点で変更されたかには注意が必要か
sub reevaluate_answer_file{
    my ($exam, $exam_answer_data_col_ref, $file, $converter_data) = @_;

    die "Invalid file (file: $file)!" if($file !~ /\/([\w\-]+)\.dat/);
    my $answer_id = $1;

    my $exam_response = ExamResponse::File->get($exam->id(), $answer_id);


    # print STDERR Data::Dumper->Dump([$exam_response]);

    # 再評価
    $CONVERTER->set_result_of_exam_response($exam_response, $exam_answer_data_col_ref, $converter_data);

    # 解答データ
    my %answer_data = ();
    $answer_data{exam_id}   = $exam_response->exam_id();
    $answer_data{userid}    = $exam_response->userid();
    $answer_data{realm}     = $exam_response->realm();
    $answer_data{fullname}  = $exam_response->fullname();
    $answer_data{answer_id} = $exam_response->answer_id();
    $answer_data{date}      = $exam_response->date();
    $answer_data{session_id}= $exam_response->session_id();

    # print STDERR Data::Dumper->Dump([$exam_response]);

    # 総得点を求める
    $answer_data{total_score} = 0;

    my @col = ();
    foreach my $each_response (@{$exam_response->responses()}){
	next if(!defined($each_response));
	next if(!defined($each_response->{index}));
	my %each_data = ();
	# 設問

	#     print STDERR  Data::Dumper->Dump([$exam_response]);
	#     die "no index $file";
	# }
	$each_data{index}  = $each_response->{index};
	# 解答
	if(defined($each_response->{user_answer})){
	    $each_data{answer} = $each_response->{user_answer};
	}else{
	    $each_data{answer} = $CONFIG{NO_ANSWER};
	}
	# 結果
	$each_data{result} =  $each_response->{result};
	$answer_data{total_score}++ if($each_data{result} == 1);
	# 誤答パターン
	if(exists($each_response->{error_label})){
	    $each_data{error_label} = $each_response->{error_label};
	}else{
	    $each_data{error_label} = [];
	}

	printf(STDERR "DEBUG: %s\n", join(", ", @{$each_data{error_label}})) if($DEBUG > 1);
	push(@col, \%each_data);
    }
    $answer_data{answers} = \@col;

    printf STDERR "DEBUG: total_score %d\n",  $answer_data{total_score} ;

    return \%answer_data;

}

# Mon Jul  8 18:47:19 2013
my @UNKNOWN_DATA_COL = ();
sub store_unknown_data{
    my ($userid, $q_index, $answer) = @_;

    if(!defined($UNKNOWN_DATA_COL[$q_index])){
	$UNKNOWN_DATA_COL[$q_index] = {};
    }
    if(!exists($UNKNOWN_DATA_COL[$q_index]->{$answer})){
	$UNKNOWN_DATA_COL[$q_index]->{$answer} = [];
    }
    push(@{$UNKNOWN_DATA_COL[$q_index]->{$answer}}, $userid);
}
#######################################
# 出力
#######################################
sub show_total_result{
    my ($exam_id, $total_result_hash_ref, $number_of_subject, $number_of_question, $converter_data) = @_;

    print("#######################################
# 全体統計情報
# - 試験ID: $exam_id
# - 設問数: $number_of_question
# - 被験者数: $number_of_subject
#######################################
エラー種別\t解答数\t全体割合\t誤答中の割合\t説明
");

    # 誤答数 = 全設問 - 正答 - 無解答
    my $number_of_error = $number_of_question * $number_of_subject - $total_result_hash_ref->{answer} - $total_result_hash_ref->{no_answer};

    foreach my $error_label (sort(keys(%{$total_result_hash_ref}))){

	my $description = $converter_data->{$error_label}->{description};
	my $value = ($total_result_hash_ref->{$error_label} / $number_of_subject);
	printf("%s\t%.2f\t%.1f\t%.1f\t%s\n",
	       $error_label, 
	       $value, 
	       ($value / $number_of_question * 100),
	       ($total_result_hash_ref->{$error_label} / $number_of_error * 100),
	       $description
	    );

# 	printf("%s & %.2f & %.1f\\\\\n",
# 	       $error_label, 
# 	       $value, 
# 	       ($value / $number_of_question * 100));
    }
}

# 学生ごとの結果出力
sub show_result{
    my ($exam_id, $user_answer_data, $number_of_question, $converter_data) = @_;

    printf("#######################################
# 個人統計情報
# - 試験ID: %s
# - 設問数: %d
# - 氏名: %s
# - ユーザID: %s\@%s
# - 時刻: %s
#######################################
エラー種別\t解答数\t割合\t説明
", 
	   $user_answer_data->{exam_id},
	   $number_of_question,
	   $user_answer_data->{fullname},
	   $user_answer_data->{userid},
	   $user_answer_data->{realm},
	   $user_answer_data->{date},
	);
    
    foreach my $error_label (sort(keys(%{$user_answer_data->{result}}))){

	my $description = $converter_data->{$error_label}->{description};
	my $value = ($user_answer_data->{result}->{$error_label});
	printf("%s\t%.2f\t%.1f\t%s\n",
	       $error_label, 
	       $value, 
	       ($value / $number_of_question * 100),
	       $description
	    );

# 	printf("%s & %.2f & %.1f\\\\\n",
# 	       $error_label, 
# 	       $value, 
# 	       ($value / $number_of_question * 100));
    }
}

# 学生ごとの結果出力
sub show_result_csv{
    my ($exam_id, $user_answer_data, $number_of_question, $converter_data, $counter) = @_;

    my @answer_col = ();
    foreach my $answer (@{$user_answer_data->{answers}}){
	my $value = $answer->{answer};
	# printf STDERR "DEBUG %s %d %s\n", $user_answer_data->{userid}, $answer->{index}, ref($value);
	
	if(ref($value) eq "ARRAY"){
	    push(@answer_col, sprintf("\"%s\"", join(',', @{$value})));
	}else{
	    $value =~ s/\s+//g;
	    
	    if($value =~ /^[\d\.\-]/){
		push(@answer_col, $value);
	    }else{
		push(@answer_col, "\"$value\"");
	    }
	}
    }
    my $student_id;
    if(defined($UT)){
	$student_id = $user_answer_data->{userid};
    }else{
	$student_id = convert_gakugei_userid_to_student_id($user_answer_data->{userid});
    }
    printf("\"%s\",\"%s\",,%d,%s,%s\n",
	   $student_id,
	   $user_answer_data->{fullname},
	   $counter, # 連番
	   join(",", @answer_col),
	   $user_answer_data->{date}
	);
}

# 東京学芸大学のユーザID を見易く出力するための処理
sub convert_gakugei_userid_to_student_id{
    my ($userid) = @_;

    if($userid =~ /^(\w)(\d{2})(\d{4})/){
	return uc($1) . $2 . '-' . $3;
    }else{
	return $userid;
    }
}
#######################################
# メイン
#######################################
# 期間指定
my @range = convert_since_and_till();

# 指定された試験の読み込み
my ($answer_data_column_names_ref, $answer_data_col_ref) = 
    read_exam_answer_file($exam_id);
my $number_of_question = scalar(@{$answer_data_col_ref});

# 変換器の読み込み
my $converter_data = $CONVERTER->read_converter_file($CONVERTER_DATA_FILE);

# 解答データファイル
my @files = get_answer_files($exam_id, \@range);

# 解答データ
my @answer_data_col;
if(defined($EVAL)){

    # 試験データ(設問の入力・出力・誤答)
    my $exam = Exam::File->get_by_id($exam_id);

    my ($exam_answer_data_column_names_ref, $exam_answer_data_col_ref, $number_of_questions_ref);
    if(defined($ANSWER_FILE)){
	# (一時的な)試験データ(設問の入力・出力・誤答)
	($exam_answer_data_column_names_ref, $exam_answer_data_col_ref, $number_of_questions_ref) = Exam::File->read_temporary_answer_file($ANSWER_FILE);
    }else{
	# 指定された試験の読み込み
	($exam_answer_data_column_names_ref, $exam_answer_data_col_ref, $number_of_questions_ref) = 
	    $exam->read_exam_answer_file();
    }
    # Thu Aug  8 18:23:51 2013
    print STDERR Data::Dumper->Dump([$exam_answer_data_column_names_ref]);
    print STDERR Data::Dumper->Dump([$exam_answer_data_col_ref]);
    print STDERR Data::Dumper->Dump([$converter_data]);
	
    @answer_data_col = map{reevaluate_answer_file($exam, $exam_answer_data_col_ref, $_, $converter_data)} @files;
}else{
    @answer_data_col = map{read_answer_file($_)} @files;
}
# 個人ごとの最高得点のみを取り出す (Sun Oct 28 16:13:20 2012)
my %userid_hash = ();
foreach my $answer_data (@answer_data_col){
    my $userid = $answer_data->{userid};

    # 学生でなければ対象外
    next if($userid =~ /(sekiya|yamaguch)/);

    if(exists($userid_hash{$userid}) && ($userid_hash{$userid}->{total_score} > $answer_data->{total_score})){
	printf(STDERR "Skip %s's answer (date:%s) because the total score is lower than current data.\n", $userid, $answer_data->{date});
	next;
    }
    $userid_hash{$userid} = $answer_data;
    printf(STDERR "DEBUG: register %s %d\n", $userid, $answer_data->{total_score});
}
@answer_data_col = values(%userid_hash);
my $number_of_answer = scalar(@answer_data_col);

# 統計データ
my $total_result_data = get_result(\@answer_data_col);

# - 学生ごとの個別
if(defined($CSV)){
    # データの見出し (Sun Jun 16 09:55:06 2013)
    # - 適宜必要に応じて修正すること
    print("student_id,fullname,kana,ID");
    for(my $i = 1; $i <= $number_of_question; $i++){
	printf(",%d", $i);
    }
    print(",memo\n");

    # データ本体
    my $counter = 0;
    map{$counter++; show_result_csv($exam_id, $_, $number_of_question, $converter_data, $counter)}
    sort {$a->{date} cmp $b->{date}} @answer_data_col;
}else{
    map{show_result($exam_id, $_, $number_of_question, $converter_data)} @answer_data_col;
}

# - 全体
show_total_result($exam_id, $total_result_data, $number_of_answer, $number_of_question, $converter_data);

print STDERR Data::Dumper->Dump(\@UNKNOWN_DATA_COL);
