#!/usr/bin/perl -w
############################################################
#
# make_demo_data.pl
#
# Created: Sun Mar 18 18:59:43 2012
# Time-stamp: <2012-05-07 17:21:48 sekiya>
#
# Usage: $0 exam_data answer_data 
############################################################
#
# - 被験者の解答データ(exam_data)と正答・誤答データ(answer_data)から
#   パターンへの合致度合を求める
#

use strict;
use utf8;
use POSIX;
use FileHandle;

use constant{
    Q_INDEX_PREFIX    => 'q',
    #
    NO_ANSWER         => '-',
    ANSWER_LABEL      => 'answer',
    #
    FIRST_LABEL_INDEX => 3,
    # 
    WORK_DIR => '/var/tmp',
    EXAM_ID  => 'id001',
    REALM    => 'gakugei',
};

use Text::CSV;

use Getopt::Long qw(:config auto_help);
GetOptions() or exit 1;

=head1 SYNOPSIS

    ./find_matching_data.pl exam_data_file answer_data_file

=head1 DESCRIPTION

日本語は通る?
=cut

# 引数
my ($EXAM_DATA_FILE, $ANSWER_DATA_FILE) = @ARGV;

# 利用法
sub usage{
    print STDERR "$0 exam_data answer_data\n";
    exit 1;
}

my $DEBUG = 1;

############################################################
# 答案データの読み込み
#
# - データ構造は以下の通り
# 学籍番号,学生氏名,カナ氏名,ID,1,2,3,4,5,6,7,8,9,10,...
# A10-0201,青池 香菜美,アオイケ カナミ,30,-3,4,3,-4,10,4,6,1,...
# ...
############################################################
sub read_exam_data_file{

    usage() if(!defined($EXAM_DATA_FILE) || ! -f $EXAM_DATA_FILE);

    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    open(my $io, "<", $EXAM_DATA_FILE) or die "$EXAM_DATA_FILE: $!";

    # 1行目は列ラベル
    my $row = $csv->getline($io);
    my @exam_data_column_names = @{$row};

    # 2行目以降は学生毎の答案データ
    my @exam_data_col = ();
    while (my $row = $csv->getline ($io)) {
	my %user_data = ();
	for(my $i = 0; $i < scalar(@exam_data_column_names); $i++){
	    my $label = $exam_data_column_names[$i];
	    if($label =~ /^\d+$/){
		$label = Q_INDEX_PREFIX . $label;
	    }
	    my $answer = $row->[$i];
	    if(!defined($answer) || length($answer) < 1){
		printf(STDERR "%s gave no answer for %s\n", 
		       $user_data{student_id},
		       $label);
		$user_data{$label} = NO_ANSWER;
	    }elsif($answer =~ /,/){
		# 配列
		my @col = split(/,/, $answer);
		printf(STDERR "%s gave array answer for %s.\n",
		       $user_data{student_id},
		       $label);
		$user_data{$label} = \@col;
	    }else{
		# 通常の数値のみの答え
		$user_data{$label} = $answer;
	    }
	}
	# ID が0の学生は，実験への協力を了承していない
	if($user_data{ID} < 1){
	    printf(STDERR "%s is not subject. Skip.\n", $user_data{student_id});
	}else{
	    push(@exam_data_col, \%user_data);
	}
    }
    $csv->eof() or $csv->error_diag();
    close($io);

    return (\@exam_data_column_names, \@exam_data_col);
}

############################################################
# 正答ならびに誤答データの読み込み
#
# index,source,input,answer,,NEGLECT_FOR_LOOP,...
# 1,a1.rb,3,-3,-
# 2,a1.rb,4,5,-
# ...
############################################################
sub read_answer_data_file{
    usage() if(!defined($ANSWER_DATA_FILE) || ! -f $ANSWER_DATA_FILE);

    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    open(my $io, "<", $ANSWER_DATA_FILE) or die "$ANSWER_DATA_FILE: $!";

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
		printf(STDERR "%s array answer for %d.\n",
		       $label,
		       $counter);

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

############################################################
# 条件に合致する誤答パターンかを判定
############################################################
# 誤答パターンに従う誤答案の設問数
sub max_maching_score{
    my ($answer_data_col_ref, $error_label) = @_;

    my $matching_score = 0;
    foreach my $answer_data (@{$answer_data_col_ref}){
	my $incorrect_answer = $answer_data->{$error_label};
	$matching_score++ if($incorrect_answer ne NO_ANSWER);
    }
    return $matching_score;
}

# 誤答パターンの一致数
sub is_matching_data{
    my ($user_data_ref, $answer_data_col_ref, $error_label) = @_;

    # どれだけマッチするか
    my $matching_score = 0;
    my @matching_index_col = ();

    # 設問毎に誤答パターンと一致するか確認する
    foreach my $answer_data (@{$answer_data_col_ref}){
	my $q_index          = Q_INDEX_PREFIX . $answer_data->{index};
	my $incorrect_answer = $answer_data->{$error_label};

	# 誤答パターンが無い
	if($incorrect_answer eq NO_ANSWER){
	    next;
	}
	
	# 当該被験者が無回答
	my $user_answer = $user_data_ref->{$q_index};
	next if($user_answer eq NO_ANSWER);

	# 比較
	if($incorrect_answer =~ /^[\d\-\.]*$/){
	    # 通常の値
	    if($user_answer == $incorrect_answer){
		push(@matching_index_col, $q_index);
		$matching_score++;
	    }
	}else{
	    # 配列の場合
	    next if($user_answer =~ /^[\d\-\w\,\.\+]+$/);

	    printf(STDERR "user_answer: %s, incorrect_answer: %s\n",
		   join(',', @{$user_answer}), 
		   join(',', @{$incorrect_answer}));
			
	    my $result = 1;
	    for(my $i = 0; $i < scalar(@{$incorrect_answer}); $i++){
		if($user_answer->[$i] != $incorrect_answer->[$i]){
		    $result = 0;
		    last;
		}
	    }
	    if($result){
		push(@matching_index_col, $q_index);
		$matching_score++;
	    }
	}
    }

    return ($matching_score, \@matching_index_col);
}

############################################################
# 出力
############################################################
sub file_out_demo_data{
    my ($exam_data, $student_pattern, $answer_data_col_ref) = @_;

    # 練習問題の実施日に基づいて，全部同じにする
    my $date = '2011-06-30_1400_00';

    # userid
    my $userid = lc($exam_data->{student_id});
    $userid =~ s/\-//;

    # ファイル名
    my $file = sprintf("%s/%s_%s_%s_%s.dat",
		       WORK_DIR, 
		       EXAM_ID,
		       REALM,
		       $userid,
		       $date);

    unlink($file) if(-f $file);
    my $fh = FileHandle->new($file, O_WRONLY|O_CREAT);
    die "Cannot open $file." if(!defined($fh));

    $fh->printf("# exam_id: %s, userid: %s, realm: %s, fullname: %s, date: %s\n# index,user_answer,result(correct:1, incorrect:0),error_label(or answer)\n",
		EXAM_ID,
		$userid,
		REALM,
		$exam_data->{fullname},
		$date);


    foreach my $answer_data (@{$answer_data_col_ref}){
	my $q_index          = Q_INDEX_PREFIX . $answer_data->{index};

	my $user_answer = $exam_data->{$q_index};
	if(defined($user_answer) && ref($user_answer) eq 'ARRAY'){
	    # 配列
	    $user_answer = '"' . join(',', @{$user_answer}) . '"';
	}

	my $result = 0;
	foreach my $error_label (@{$student_pattern->{$q_index}}){
	    if($error_label eq ANSWER_LABEL){
		$result = 1;
		last;
	    }
	}
	$fh->printf("%d,%s,%s,\"%s\"\n",
		    $answer_data->{index},
		    $user_answer,
		    $result,
		    join(",", @{$student_pattern->{$q_index}})
	    );
    }

    $fh->close();
}
############################################################
# メイン
############################################################
my ($exam_data_column_names_ref, $exam_data_col_ref) = read_exam_data_file();
my ($answer_data_column_names_ref, $answer_data_col_ref) = read_answer_data_file();

# 被験者数
my $number_of_subject  = scalar(@{$exam_data_col_ref});
# 設問数
my $number_of_question = scalar(@{$answer_data_col_ref});

# どのパターンに適合するかを記録
my %student_pattern_hash = ();
foreach my $exam_data (@{$exam_data_col_ref}){
    my $student_id = $exam_data->{student_id};
    my %student_pattern = ();
    $student_pattern{student_id} = $student_id;

    # 設問毎に誤答パターンと一致するか確認する
    foreach my $answer_data (@{$answer_data_col_ref}){
	my $q_index          = Q_INDEX_PREFIX . $answer_data->{index};
	$student_pattern{$q_index} = [];
    }
    $student_pattern_hash{$student_id} = \%student_pattern;
}

#
# 確認結果
#
for(my $i = FIRST_LABEL_INDEX; $i < scalar(@{$answer_data_column_names_ref}); $i++){

    # 誤答(正答も含む)パターン名
    my $error_label = $answer_data_column_names_ref->[$i];

#     # ファイルに出力
#     my $file = $error_label . POSIX::strftime("_%Y-%m-%d_%H%M.dat", localtime());
#     unlink($file) if(-f $file);
#     my $fh = FileHandle->new($file, O_WRONLY|O_CREAT);
#     die "Cannot open $file." if(!defined($fh));

#     # コメント
#     $fh->printf("#\n# %s\n#\n# <%s>\n",
# 		$error_label,
# 		POSIX::strftime("%c", localtime()));

    my $total = 0;
    my $max_score = max_maching_score($answer_data_col_ref, $error_label);
    my @matching_score_col = ();
    for(my $i = 0; $i < $max_score; $i++){
	$matching_score_col[$i] = 0;
    }
    my @print_later_col = ();

    foreach my $exam_data (@{$exam_data_col_ref}){
	$total++;

	# 学生ID
	my $student_id = $exam_data->{student_id};
	my ($score, $matching_index_col_ref) = is_matching_data($exam_data, $answer_data_col_ref, $error_label);
# 	push(@print_later_col, sprintf("%s,%d,\"%s\"\n",
# 				       # $exam_data->{fullname},
# 				       $student_id,
# 				       $score,
# 				       join(', ', @{$matching_index_col_ref})));
# 	     # print STDERR "DEBUG: $score\n";
	$matching_score_col[$score]++;

	# パターンの記録
	my $student_pattern = $student_pattern_hash{$student_id};
	foreach my $q_index (@{$matching_index_col_ref}){
	    push(@{$student_pattern->{$q_index}}, $error_label);
	}
    }
}

# ファイル出力
foreach my $exam_data (@{$exam_data_col_ref}){

    # 学生ID
    my $student_id = $exam_data->{student_id};

    # 対応する (誤答)パターン
    my $student_pattern = $student_pattern_hash{$student_id};

    # 出力
    file_out_demo_data($exam_data, $student_pattern, $answer_data_col_ref);

}

