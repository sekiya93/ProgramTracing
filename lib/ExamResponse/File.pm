############################################################
#
# ExamResponse::File
#
# Time-stamp: <2013-07-08 18:37:21 sekiya>
#
############################################################
# - 試験に対するユーザの解答データ

package ExamResponse::File;

use Moose;

use constant{
    CONFIG_DIR        => 'conf',
};
# use constant ATTRIBUTE_NAMES => ('id', 'name', 'registered', 'modified', 'is_open', 'description');
# use constant QUEST_ATTRIBUTE_NAMES => ('index', 'source', 'input', 'answer');

use Config::Simple;
use Text::CSV;
use POSIX;
use FileHandle;

use Utility;

my %CONFIG;
my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

our %RESPONSE_HASH = ();

#######################################
# 属性定義
#######################################
has 'exam_id' => (
    is => 'rw'
);

has 'answer_id' => (
    is => 'rw'
);

has 'userid' => (
    is => 'rw'
);

has 'realm' => (
    is => 'rw'
);

has 'fullname' => (
    is => 'rw'
);

has 'date' => (
    is => 'rw'
);

has 'session_id' => (
    is => 'rw'
);

has 'responses' => (
    is => 'rw'
);

has 'score' => (
    is => 'rw'
);

has 'user_error_patterns' => (
    is => 'rw'
    );

#######################################
# オブジェクト生成
#######################################
sub BUILD{
    my $self = shift;
    $self->date(POSIX::strftime("%Y-%m-%d_%H%M_%S", localtime()));
    return $self;
}

sub get{
    my ($self, $exam_id, $answer_id) = @_;

    $exam_id   =~ s/(\.\.|[><\/])//g;
    $answer_id =~ s/(\.\.|[><\/])//g;

    return _read_answer_and_correct_data($exam_id, $answer_id);
}

#######################################
# 属性
#######################################
sub get_response{
    my ($self, $q_index) = @_;

    return $self->responses()->[$q_index];
}

sub set_response{
    my ($self, $q_index, $user_answer, $result, $error_labels_ref) = @_;

    my %each_response = ();
    $each_response{index}       = $q_index;
    if(defined($user_answer)){
	$each_response{user_answer} = $user_answer;
    }else{
	# Mon Jul  8 17:47:09 2013
	$each_response{user_answer} = $CONFIG{NO_ANSWER};
    }
    $each_response{result}      = $result;
    $each_response{error_label} = $error_labels_ref;

    $self->responses([]) if(!defined($self->responses()));

    $self->responses()->[$q_index] = \%each_response;

    return $self->get_response($q_index);
}

sub set_each_response{
    my ($self, $each_response) = @_;

    return $self->responses()->[$each_response->{index}] = $each_response;
}
    
#######################################
# ファイル読み書き
#######################################
sub _read_answer_and_correct_data{
    my ($exam_id, $answer_id) = @_;

    my $dir = sprintf("%s/%s", $CONFIG{ANSWER_DIR}, $exam_id);
    return undef if(!-d $dir);

    my $file = sprintf("%s/%s.dat",
		       $dir,
		       $answer_id);

    my $obj = ExamResponse::File->new();
    $obj->answer_id($answer_id);

    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    open(my $io, "<", $file) or die "$file: $!";

    # 誤答パターン
    my %result_data = ();
    my $score = 0;
    while (my $row = $csv->getline($io)) {
	if($row->[0] =~ /^\#/){
	    # コメント行の解釈
	    # - データの中にカンマが入らないこと...
	    foreach my $comment_entry (@{$row}){
		next if($comment_entry !~ /(\w+):\s*(\S.+\S)/);
		$obj->$1($2);
	    }
	}else{
	    # 設問毎の解答行
	    # - 項番(index),ユーザの解答(user_answer),正誤(result),誤答パターン(error_label)
	    my ($q_index, $user_answer_str, $correct, $error_label_str) = @{$row};
	    next if(!defined($q_index) || $q_index < 1);

	    # ユーザの解答
	    my $user_answer = Utility::string_to_value($user_answer_str);

	    # 項番ラベル
	    $error_label_str =~ s/"//g;
	    my @col = split(/,/, $error_label_str);

	    # 設問毎の解答データの登録
	    $obj->set_response($q_index, $user_answer, $correct, \@col);

	    # 得点
	    $score += $correct;
	}
    }
    $csv->eof() or $csv->error_diag();
    close($io);

    $obj->score($score);

    return $obj;
}

# 書き込み
sub _write_answer_data{
    my ($self, $session) = @_;

    my $dir = sprintf("%s/%s", $CONFIG{ANSWER_DIR}, $self->exam_id());
    mkdir($dir) if(!-d $dir);

    my $date_string = $self->date();
    $self->answer_id(sprintf("%s_%s_%s_%s",
			     $self->exam_id(),
			     $self->realm(),
			     $self->userid(),
			     $date_string));
    my $session_id = 'unknown';
    if(defined($session)){
	$session_id = $session->id();
    }

    my $file = sprintf("%s/%s.dat",
		       $dir,
		       $self->answer_id());

    my $fh = FileHandle->new($file, O_WRONLY|O_CREAT);
    die "Cannot open $file." if(!defined($fh));

    $fh->printf("# exam_id: %s, userid: %s, realm: %s, fullname: %s, answer_id: %s, date: %s, session_id: %s\n# index,user_answer,result(correct:1, incorrect:0),error_label(or answer)\n",
		$self->exam_id(),
		$self->userid(),
		$self->realm(),
		$self->fullname(),
		$self->answer_id(),
		$date_string,
		$session_id
	);
		
    foreach my $each_response (@{$self->responses()}){
	next if(!defined($each_response));
	my $answer_string = Utility::value_to_string($each_response->{user_answer});
	$answer_string = '"' . $answer_string . '"' if($answer_string =~ /,/);
	$fh->printf("%s,%s,%d,\"%s\"\n", 
		    $each_response->{index},
		    $answer_string,
		    $each_response->{result},
		    join(",", @{$each_response->{error_label}}));
    }

    $fh->close();
}

sub save{
    my ($self, $session) = @_;

    return $self->_write_answer_data($session);
}

#######################################
# 解答一覧の取得
#######################################
# - $exam_id: 試験ID
# - $answer_order: ソート順(未使用 Tue Sep  4 14:20:27 2012)
# - $number_of_questions_ref: 誤答パターンに一致する設問数
#   {NEGLECT_FOR_LOOP => 8, CHANGE_VARIABLE_IN_LOOP => ?, ...}
sub get_list{
    my ($self, $exam_id) = @_;

    my $dir = sprintf("%s/%s", $CONFIG{ANSWER_DIR}, $exam_id);
    return () if(!-d $dir);

    my @col = ();
    foreach my $file (glob("$dir/$exam_id" . '*')){
	next if($file !~ /\/([^\/]+)\.dat/);
	my $answer_id = $1;
	my $obj = _read_answer_and_correct_data($exam_id, $answer_id);
	push(@col, $obj);
    }

    return @col;
}

#######################################
# 誤答パターンの判定
#######################################
# - ConverterEngine に持って行くべきか? (Sun Sep 23 13:31:58 2012)
# - 入力
# -- $number_of_questions_ref
sub set_error_patterns{
    my ($self, $number_of_questions_ref) = @_;

    my @user_error_patterns = ();

    # 誤答パターン数え上げ
    my %error_pattern_counter = ();

    foreach my $error_label (keys(%{$number_of_questions_ref})){
	$error_pattern_counter{$error_label} = 0;
    }

    # 各設問毎の誤答パターンを調べる
    if(ref($self->responses()) eq 'ARRAY'){
	foreach my $each_response (@{$self->responses()}){
	    next if(!defined($each_response));
	    
	    foreach my $error_label (@{$each_response->{error_label}}){
		$error_pattern_counter{$error_label}++;
	    }
	}
    }

    # 全体での判定
    while(my ($error_label, $number) = each(%{$number_of_questions_ref})){
	push(@user_error_patterns, $error_label) if($error_pattern_counter{$error_label} >= $number * $CONFIG{ERROR_PATTERN_MIN});
    }

    $self->user_error_patterns(\@user_error_patterns);
}

#######################################
# ユーティリティ
#######################################
# 値を文字列に変換
# - 配列の処理を整理するために用いる
# sub _value_to_string{
#     my ($value) = @_;

#     if(ref($value) eq 'ARRAY'){
# 	return '"[' . join(', ', @{$value}) . ']"';
#     }else{
# 	return $value;
#     }
# }

# # 文字列を値変換
# # - 配列の処理を整理するために用いる
# sub _string_to_value{
#     my ($string) = @_;

#     $string =~ s/\s//g;

#     # 今後は [] をつけた形でデータを保存
#     if($string =~ /^\[(.+)\]$/ || $string =~ /^(.+,.+)$/){
# 	$string = $1;
# 	my @col = ();
#  	map{push(@col, eval($_))} split(/,/, $string);
# 	return \@col;
#     }else{
# 	return $string;
#     }
# }

# # 書き込み
# # - 実運用の上では考えるべきことが多そう
# # - lock は... とりあえず考えない?
# sub save{
#     my ($self) = shift;

#     $self->read_csv_file();

#     my $tmp_file = sprintf("%s/exam_list.dat.tmp", $CONFIG{EXAM_DIR});

#     my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
#     open(my $io, ">", $tmp_file) or die "$tmp_file: $!";
#     while(my ($key, $obj) = each(%EXAM_HASH)){
# 	my @col = ();
# 	foreach my $attribute_name (attribute_names()){
# 	    push(@col, $obj->$attribute_name());
# 	}
# 	$csv->print($io, \@col);
#     }
#     close($io);

#     my $target_file = sprintf("%s/exam_list.dat", $CONFIG{EXAM_DIR});
#     my $suffix = POSIX::strftime("%Y-%m-%d_%H%M_%S", localtime());
#     my $backup_file = sprintf("%s/exam_list.dat.%s", $CONFIG{BACKUP_DIR}, $suffix);
#     rename($target_file, $backup_file);
#     rename($tmp_file, $target_file);
    
#     # debug
#     printf(STDERR "DEBUG: save (%d)\n", time());
# }

__PACKAGE__->meta->make_immutable;

no Moose;

1;
