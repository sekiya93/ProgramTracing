#!/usr/bin/perl -w
############################################################
#
# データの集計用スクリプト (2012-05-01)
#
# Time-stamp: <2013-06-16 10:35:58 sekiya>
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

# use Template;
# # my $TEMPLATE_CONFIG = {INCLUDE_PATH => '/usr/local/plack/tracing/template'};

# use CFIVE::CfiveUser;

my $DEBUG = 1;

my ($DATE_SINCE, $DATE_TILL, $exam_id, $CSV, $UT);
use Getopt::Long qw(:config auto_help);
GetOptions("since=s"   => \$DATE_SINCE,
	   "till=s"    => \$DATE_TILL,
	   "exam_id=s" => \$exam_id,
	   "csv"       => \$CSV,
	   "ut"        => \$UT,
    ) or exit 1;
die "No exam ID!" if(!defined($exam_id));

=head1 SYNOPSIS

    ./show_questionnaire.pl [--since YYYY-mm-dd] [--till YYYY-mm-dd] --exam_id exam_id

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

    return @result;
}

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

#######################################
# 解答
#######################################

# ファイルに保存して有った解答結果を読込む

# $answer_data->{exam_id}
#            ->{userid}
#            ->{realm}
#            ->{fullname}
#            ->{date}
#            ->{answers} = []
# $answer->{index}
#        ->{answer}
#        ->{result}
#        ->{error_label}
sub read_questionnaire_file{
    my ($file) = @_;

    my $csv = Text::CSV->new ({ binary => 1});
    open(my $io, "<", $file) or die "$file: $!";

    my %questionnaire_data = ();
    # 1行目は，コメント行として基本情報を書いておく
    my $first_line = $csv->getline($io);
    foreach my $data (@{$first_line}){
	$data =~ s/^[\#\s]+//;
	next if($data !~ /^(\w+):\s*(\S.+)/);
	$questionnaire_data{$1} = $2;
	printf(STDERR "DEBUG: key: %s, value: %s\n", $1, $2) if($DEBUG);
    }

    # answer_id をファイル名から取得 (Tue Nov 20 09:04:55 2012)
    if($file =~ /_(\d{4}\-\d{2}\-\d{2}_\d{4}_\d{2})/){
	$questionnaire_data{answer_id} = $1;
    }else{
	print STDERR "DEBUG: Could not get answer_id from $file.\n";
	$questionnaire_data{answer_id} = '-';
    }

    my @col = ();
    while (my $row = $csv->getline($io)) {
	next if($row->[0] =~ /^\#/); # コメント行をスキップ
	my %each_data = ();

	# 設問
	$each_data{index} = $row->[0];
	# アンケート回答
	$each_data{questionnaire} = $row->[1];

	push(@col, \%each_data);
    }

    if(!$csv->eof()){
	print STDERR "The following error occurred while reading $file.\n";
	die $csv->error_diag();
    };
    close($io);

    $questionnaire_data{questionnaires} = \@col;

    return \%questionnaire_data;
}

# アンケート内容の回収
sub get_questionnaire_files{
    my ($exam_id, $range_ref) = @_;

    my $questionnaire_dir = sprintf("%s/%s", $CONFIG{QUESTIONNAIRE_DIR}, $exam_id);
    die "Cannot open the directory $questionnaire_dir." if(!-d $questionnaire_dir);

    # 拡張子が dat であることが前提
    my @tmp_files = glob("$questionnaire_dir/*.dat");

    # 当面は since のみ
    if(!defined($range_ref->[0])){
	return @tmp_files;
    }
    my $since = $range_ref->[0];

    my @questionnaire = ();
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
	if(DateTime->compare($file_dt, $range_ref->[0]) >= 0){
	    push(@questionnaire, $file);
	}
    }

    return @questionnaire;
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
エラー種別\t解答数\t割合\t説明
");

    foreach my $error_label (sort(keys(%{$total_result_hash_ref}))){

	my $description = $converter_data->{$error_label}->{description};
	my $value = ($total_result_hash_ref->{$error_label} / $number_of_subject);
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
sub show_result{
    my ($exam_id, $user_questionnaire_data, $number_of_question, $converter_data) = @_;

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
	   $user_questionnaire_data->{exam_id},
	   $number_of_question,
	   $user_questionnaire_data->{fullname},
	   $user_questionnaire_data->{userid},
	   $user_questionnaire_data->{realm},
	   $user_questionnaire_data->{date},
	);
    
    foreach my $error_label (sort(keys(%{$user_questionnaire_data->{result}}))){

	my $description = $converter_data->{$error_label}->{description};
	my $value = ($user_questionnaire_data->{result}->{$error_label});
	printf("%s\t%.2f\t%.1f\t%s\n",
	       $error_label, 
	       $value, 
	       ($value / $number_of_question * 100),
	       $description
	    );
    }
}

# 学生ごとの結果出力
sub show_result_csv{
    my ($exam_id, $user_questionnaire_data, $number_of_question, $converter_data, $counter) = @_;

    my @questionnaire_col = ();
    foreach my $questionnaire (@{$user_questionnaire_data->{questionnaires}}){
	my $value = $questionnaire->{questionnaire};
	printf STDERR "DEBUG %s %d %s\n", $user_questionnaire_data->{userid}, $questionnaire->{index}, ref($value);
	
	push(@questionnaire_col, "\"$value\"");
    }
    my $student_id;
    if(defined($UT)){
	$student_id = $user_questionnaire_data->{userid};
    }else{
	$student_id = convert_gakugei_userid_to_student_id($user_questionnaire_data->{userid});
    }
    # student_id,fullname,kana,ID
    printf("\"%s\",\"%s\",,%d,%s,%s,%s\n",
	   $student_id,
	   $user_questionnaire_data->{fullname},
	   $counter, # id (連番)
	   join(",", @questionnaire_col),
	   $user_questionnaire_data->{answer_id},
	   $user_questionnaire_data->{date}
	);


    # printf("\"%s\",\"%s\",,,%s\n",
    # 	   convert_gakugei_userid_to_student_id($user_questionnaire_data->{userid}),
    # 	   $user_questionnaire_data->{fullname},
    # 	   join(",", @questionnaire_col)
    # 	);
}

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
my $converter_data = read_converter_file();

# 解答データファイル
my @files = get_questionnaire_files($exam_id, \@range);
my $number_of_questionnaire = scalar(@files);

# 解答データ
my @questionnaire_data_col = map{read_questionnaire_file($_)} @files;

# - 学生ごとの個別
if(defined($CSV)){
    # データの見出し (Sun Jun 16 09:55:06 2013)
    # - 適宜必要に応じて修正すること
    print("student_id,fullname,kana,ID");
    for(my $i = 1; $i <= $number_of_question; $i++){
	printf(",%d", $i);
    }
    print(",memo1,memo2\n");

    my $counter = 0;
    map{$counter++; show_result_csv($exam_id, $_, $number_of_question, $converter_data, $counter)} 
    sort {$a->{answer_id} cmp $b->{answer_id}} @questionnaire_data_col;
}else{
    map{show_result($exam_id, $_, $number_of_question, $converter_data)} @questionnaire_data_col;
}
