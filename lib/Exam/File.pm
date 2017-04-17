############################################################
#
# Exam::File
#
# Time-stamp: <2013-08-08 16:51:04 sekiya>
#
############################################################
# - 答案情報の実体はファイルで管理するが，外部のプログラムからは
#   オブジェクトとして取扱い可能とする．
# - 設問の type として以下を考える
# -- trace: 従来通りのトレーシング
# -- inverse_trace: input を入力では無く出力と解釈して，その出力を
#    得られる入力値を求める
package Exam::File;

use Moose;
use utf8;

use constant{
    CONFIG_DIR        => 'conf',
    #
    QUEST_TYPE_INVERSE              => "inverse_trace",
    QUEST_TYPE_TRACE_MORE_THAN_ONE  => "trace_more_than_one",
    QUEST_TYPE_OUTPUT               => "trace_output",
    QUEST_TYPE_OUTPUT_MORE_THAN_ONE => "trace_output_more_than_one",
    QUEST_TYPE_OUTPUT_SIMPLE        => "trace_output_simple",
};

use constant ATTRIBUTE_NAMES => ('id', 'name', 'registered', 'modified', 'is_open_to_eccs', 'is_open_to_gakugei', 'description');
use constant QUEST_ATTRIBUTE_NAMES => ('index', 'source', 'input', 'answer', 'type');

use Config::Simple;
use Text::CSV;
use POSIX;

my %CONFIG;
my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

our %EXAM_HASH = ();
our $READ_TIME = 0;

use Code::File;
use Utility;

#######################################
# 属性定義
#######################################
has 'id' => (
    is => 'rw'
);

has 'name' => (
    is => 'rw'
);

has 'registered' => (
    is => 'rw'
);

has 'modified' => (
    is => 'rw'
);

has 'description' => (
    is => 'rw'
);

# Bool accepts 1 for true, and undef, 0, or the empty string as false.
# (http://search.cpan.org/~doy/Moose-2.0603/lib/Moose/Manual/Types.pod)
# has 'is_open' => (
#     is      => 'rw',
#     isa     => 'Bool',
#     default => 0,
# );

has 'is_open_to_eccs' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

has 'is_open_to_gakugei' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

# has 'read_answers' => (
#     is      => 'rw',
#     isa     => 'Int',
#     default => 0
# );

#######################################
# 初期化
#######################################
# 試験問題の取得
# id,name,registered,modified,description
# sub BUILD{
#     my $self = shift;

#      my $file = sprintf("%s/exam_list.dat", $CONFIG{EXAM_DIR});
#     my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
#     open(my $io, "<", $file) or die "$file: $!";

#     while (my $row = $csv->getline ($io)) {
# 	# コメント行はスキップ
# 	next if($row->[0] =~ /^#/);
# 	next if($row->[0] ne $self->id());
	
# 	$self->name($row->[1]);
# 	$self->registered($row->[2]);
# 	$self->modified($row->[3]);
# 	$self->description($row->[4]);
#     }
#     $csv->eof() or $csv->error_diag();
#     close($io);

#     return $self;
# }

#######################################
# ファイル読書
#######################################
sub read_csv_file{
    my $file = sprintf("%s/exam_list.dat", $CONFIG{EXAM_DIR});

    # mtime の比較
    my @col = stat($file);
    return 0 if($col[9] < $READ_TIME);
    $READ_TIME = time();

    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    open(my $io, "<", $file) or die "$file: $!";
    while (my $row = $csv->getline ($io)) {
	# コメント行はスキップ
	next if($row->[0] =~ /^#/);
	my $obj = Exam::File->new(
	    id          => $row->[0], 
	    name        => $row->[1], 
	    registered  => $row->[2], 
	    modified    => $row->[3], 
	    is_open_to_eccs    => $row->[4], 
	    is_open_to_gakugei => $row->[5], 
	    description => $row->[6]
	    );
	$EXAM_HASH{$row->[0]} = $obj;
    }
    $csv->eof() or $csv->error_diag();
    close($io);

    # debug
    # printf(STDERR "DEBUG: read_csv_file (%d)\n", time());
}

# 書き込み
# - 実運用の上では考えるべきことが多そう
# - lock は... とりあえず考えない?
sub save{
    my ($self) = shift;

    $self->read_csv_file();

    my $tmp_file = sprintf("%s/exam_list.dat.tmp", $CONFIG{EXAM_DIR});

    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    open(my $io, ">", $tmp_file) or die "$tmp_file: $!";
    while(my ($key, $obj) = each(%EXAM_HASH)){
	my @col = ();
	foreach my $attribute_name (attribute_names()){
	    push(@col, $obj->$attribute_name());
	}
	$csv->print($io, \@col);
    }
    close($io);

    my $target_file = sprintf("%s/exam_list.dat", $CONFIG{EXAM_DIR});
    my $suffix = POSIX::strftime("%Y-%m-%d_%H%M_%S", localtime());
    my $backup_file = sprintf("%s/exam_list.dat.%s", $CONFIG{BACKUP_DIR}, $suffix);
    rename($target_file, $backup_file);
    rename($tmp_file, $target_file);
    
    # debug
    printf(STDERR "DEBUG: save (%d)\n", time());
}

#######################################
# オブジェクトの取得
#######################################
# - クラス変数の代りに %EXAM_HASH を用いる
# - ファイルが更新されるまでは，id が同じオブジェクトは
#   同一のオブジェクトになる
# -- 一方を修正すると他方にも修正が反映される

# 一覧取得
sub exam_list{

    read_csv_file();

    return values(%EXAM_HASH);
}

# 一個
sub get_by_id{
    my ($self, $id) = @_;

    read_csv_file();

    $id =~ s/[^\w\-\.]//g;

    if(exists($EXAM_HASH{$id})){
	return $EXAM_HASH{$id};
    }else{
	return undef;
    }
}

#######################################
# 属性名
#######################################
sub attribute_names{
    my ($self) = shift;

    return (ATTRIBUTE_NAMES);
}

sub quest_attribute_names{
    my ($self) = shift;

    return (QUEST_ATTRIBUTE_NAMES);
}

sub modify_attributes{
    my ($self, $value_hash_ref) = @_;

    $self->modified(POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime()));
    
    if($value_hash_ref->{name} =~ /(\S+.+\S)/){
	my $name = $1;
	$name =~ s/[\r\n]//g;
	$self->name($name);
    }
    if($value_hash_ref->{description} =~ /(\S+.+\S)/){
	my $description = $1;
	$description =~ s/[\r\n]//g;
	$self->description($description);
    }
    # $self->is_open($value_hash_ref->{is_open});
    $self->is_open_to_eccs($value_hash_ref->{is_open_to_eccs});
    $self->is_open_to_gakugei($value_hash_ref->{is_open_to_gakugei});
}

# 設問種別
sub quest_types{

    my %hash = ();
    my $num = scalar(@{$CONFIG{QUEST_TYPES}});
    for(my $i = 0; $i < $num; $i++){
	$hash{$CONFIG{QUEST_TYPES}->[$i]} = $CONFIG{QUEST_TYPE_NAMES}->[$i];
    }

    return \%hash;
}

#######################################
# 設問
#######################################
# $CONFIG{EXAM_DIR}/$self->id()/answer.csv から
# 設問情報を読込む
# - type を追加
sub read_exam_answer_file{
    my ($self) = @_;

    my $exam_id = $self->id();

    my $file = sprintf("%s/%s/answer.csv", $CONFIG{EXAM_DIR}, $exam_id);
    my @col = stat($file);

    # return 0 if($col[9] < $self->read_answers());

    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    open(my $io, "<", $file) or die "$file: $!";
    # $self->read_answers($col[9]);

    # 1行目は列ラベル
    my $row = $csv->getline($io);
    my @answer_data_column_names = @{$row};

    # 誤答パターンに一致する設問数...の初期化
    my %number_of_questions = ();
    for(my $i = $CONFIG{FIRST_INDEX_OF_ERROR_LABEL} + 1; $i < scalar(@answer_data_column_names); $i++){
	my $error_label = $answer_data_column_names[$i];
	$number_of_questions{$error_label} = 0;
    }

    # 2行目以降は設問毎の正答ならびに誤答データ
    my @answer_data_col = ();
    my $counter = 1;
    while (my $row = $csv->getline ($io)) {
	# コメント行
	next if($row->[0] =~ /^#/);
 
	my %answer_data = ();
	for(my $i = 0; $i < scalar(@answer_data_column_names); $i++){
	    # ラベル (NEGLECT_FOR_LOOP, ..など)
	    my $label = $answer_data_column_names[$i];

	    # 正答又は誤答
	    my $answer = $row->[$i];
	    $answer_data{$label} = Utility::string_to_value($answer);
	    # printf STDERR "DEBUG %s: %s\n", $label, $answer_data{$label};
	}
	$counter++;
	push(@answer_data_col, \%answer_data);
    }
    $csv->eof() or $csv->error_diag();
    close($io);

    foreach my $answer_data_ref (@answer_data_col){
	# 正答
	# my $correct_answer = $answer_data_ref->{answer};
	
	# 設問種別に関する過渡的な措置 
	# (Fri Sep 21 16:43:04 2012)
	if(!defined($answer_data_ref->{type}) || $answer_data_ref->{type} eq ''){
	    $answer_data_ref->{type} = $CONFIG{QUEST_TYPES}->[0];
	}

	for(my $i = $CONFIG{FIRST_INDEX_OF_ERROR_LABEL} + 1; $i < scalar(@answer_data_column_names); $i++){
	    my $error_label = $answer_data_column_names[$i];
	    #
	    next if($error_label eq 'type'); # Fri Sep 21 16:21:14 2012

	    my $error_answer = $answer_data_ref->{$error_label};
	    if(!defined($error_answer)){
		$answer_data_ref->{$error_label} = $CONFIG{NO_ANSWER}; # 未設定
		next;
	    }
	    next if($error_answer eq $CONFIG{NO_ANSWER}); # 無解答
	    # 正答と同じものは無い筈?
	    $number_of_questions{$error_label}++;
	}
    }

    # 設問文の読み込み (Sat Jun  8 21:02:55 2013)
    my $quest_sentence_col_ref = $self->read_quest_sentence_file();
    if(defined($quest_sentence_col_ref)){
	foreach my $answer_data (@answer_data_col){
	    my $quest_index = $answer_data->{index};
	    $answer_data->{sentence} = $quest_sentence_col_ref->[$quest_index] if(exists($quest_sentence_col_ref->[$quest_index]));
	}
    }

    return (\@answer_data_column_names, \@answer_data_col, \%number_of_questions);
}

# 設問情報の取得
# - 入力: 設問インデックス
# - 出力: 設問情報
# - read_exam_answer_file()を実行して，
sub get_quest_data{
    my ($self, $quest_index) = @_;

    # 設問番号(index)は数値のみ
    $quest_index =~ s/[^\d]//g;
    # print STDERR "DEBUG: quest_index $quest_index\n";

    # 指定された試験の読み込み
    my ($answer_data_column_names_ref, $answer_data_col_ref, $number_of_questions_ref) = $self->read_exam_answer_file();

    my $target_answer_data;

    foreach my $answer_data (@{$answer_data_col_ref}){
	# print STDERR Data::Dumper->Dump([$answer_data]);
	if($answer_data->{index} eq $quest_index){
	    $target_answer_data = $answer_data;
	    last;
	}
    }

    return $target_answer_data;
}

# 設問情報の更新
# - answer.csv への書き込みまでを行う
sub set_quest_data{
    my ($self, $quest_data_ref) = @_;

    # 指定された試験の読み込み
    my ($answer_data_column_names_ref, $answer_data_col_ref, $number_of_questions_ref) = $self->read_exam_answer_file();

    # answer_data_column_names_ref の更新 (Mon Jul  8 15:35:10 2013)
    my %column_names_hash = ();
    map {if($_ !~ /^(index|source|input|answer|type)$/){
	$column_names_hash{$_} = 1}} @{$answer_data_column_names_ref};

    foreach my $answer_data (@{$answer_data_col_ref}){
	# print STDERR Data::Dumper->Dump([$answer_data]);
	if($answer_data->{index} eq $quest_data_ref->{index}){
	    foreach my $key (keys(%{$quest_data_ref})){
		$answer_data->{$key} = $quest_data_ref->{$key};
		next if($key =~ /^(index|source|input|answer|type)$/);
		$column_names_hash{$key} = 1;
	    }
	}
    }

    my @new_answer_data_column_names = ('index', 'source', 'input', 'answer');
    map {push(@new_answer_data_column_names, $_)} sort(keys(%column_names_hash));
    push(@new_answer_data_column_names, 'type');


    # ファイルに保存
    # $self->write_exam_answer_file($answer_data_column_names_ref, $answer_data_col_ref);
    $self->write_exam_answer_file(\@new_answer_data_column_names, $answer_data_col_ref);
}

# 設問情報の更新
# - answer.csv への書き込みまでを行う
sub write_exam_answer_file{
    my ($self, $answer_data_column_names_ref, $answer_data_col_ref) = @_;

    # ファイルに保存
    my $tmp_file = sprintf("%s/%s_answer.csv.%d", $CONFIG{TMP_DIR}, $self->id(), $$);

    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    open(my $io, ">", $tmp_file) or die "$tmp_file: $!";
    $csv->print($io, $answer_data_column_names_ref);
    foreach my $answer_data (@{$answer_data_col_ref}){
	my @col = 
	    map{
		if(exists($answer_data->{$_})){
		    Utility::value_to_string($answer_data->{$_})
		}else{
		    $CONFIG{NO_ANSWER}
	    }
	} @{$answer_data_column_names_ref};
	$csv->print($io, \@col);
    }
    close($io);

    my $target_dir  = sprintf("%s/%s/", $CONFIG{EXAM_DIR}, $self->id());
    mkdir($target_dir) if(! -d $target_dir);
    my $target_file = sprintf("%s/%s/answer.csv", $CONFIG{EXAM_DIR}, $self->id());
    my $suffix = POSIX::strftime("%Y-%m-%d_%H%M_%S", localtime());
    my $backup_file = sprintf("%s/%s_answer.csv.%s", $CONFIG{BACKUP_DIR}, $self->id(), $suffix);
    rename($target_file, $backup_file);
    rename($tmp_file, $target_file);
    
    # debug
    printf(STDERR "DEBUG: save (%d)\n", time());
}

# 設問の追加
# - 設問番号以外は空っぽ
sub add_quest_data{
    my ($self) = @_;

    # 指定された試験の読み込み
    my ($answer_data_column_names_ref, $answer_data_col_ref, $number_of_questions_ref) = $self->read_exam_answer_file();

    my $max_index = 0;
    foreach my $answer_data (@{$answer_data_col_ref}){
	$max_index = $answer_data->{index} if($answer_data->{index} > $max_index);
    }
    my $new_data = {};
    map {$new_data->{$_} = ''} @{$answer_data_column_names_ref};
    $new_data->{index} = $max_index + 1;
    push(@{$answer_data_col_ref}, $new_data);

    # ファイルに保存
    $self->write_exam_answer_file($answer_data_column_names_ref, $answer_data_col_ref);
}

# 設問の削除
# - index で指定
sub delete_quest_data{
    my ($self, $index) = @_;

    # 設問データの読込み
    my ($answer_data_column_names_ref, $answer_data_col_ref, $number_of_questions_ref) = $self->read_exam_answer_file();

    my @new_answer_data_col = ();
    my $new_index = 1;
    foreach my $answer_data (@{$answer_data_col_ref}){
	next if($answer_data->{index} == $index);
	$answer_data->{index} = $new_index;
	$new_index++;
	push(@new_answer_data_col, $answer_data);
    }

    # ファイルに保存
    $self->write_exam_answer_file($answer_data_column_names_ref, \@new_answer_data_col);
}


# 指定した設問を一つ上に
# - index で指定
# - 順序の入れ替えに用いる
sub move_forward_quest_data{
    my ($self, $index) = @_;

    # 設問データの読込み
    my ($quest_data_column_names_ref, $quest_data_col_ref, $number_of_questions_ref) = $self->read_exam_answer_file();

    my @new_quest_data_col = ();
    my $new_index = 1;
    my $previous_quest_data;
    foreach my $quest_data (@{$quest_data_col_ref}){
	if($quest_data->{index} == $index && defined($previous_quest_data)){
	    pop(@new_quest_data_col);
	    $quest_data->{index}          = $previous_quest_data->{index};
	    $previous_quest_data->{index} = $index;
	    push(@new_quest_data_col, $quest_data);
	    push(@new_quest_data_col, $previous_quest_data);
	}else{
	    push(@new_quest_data_col, $quest_data);
	    $previous_quest_data = $quest_data;
	}
    }

    # ファイルに保存
    $self->write_exam_answer_file($quest_data_column_names_ref, \@new_quest_data_col);
}

# 一時的に生成された answer_file を読み込む
# - Thu Aug  8 16:51:03 2013
sub read_temporary_answer_file{
    my ($self, $file) = @_;

    die "Cannot open $file." if(!-f $file);
    
    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    open(my $io, "<", $file) or die "$file: $!";

    # 1行目は列ラベル
    my $row = $csv->getline($io);
    my @answer_data_column_names = @{$row};

    # 誤答パターンに一致する設問数...の初期化
    my %number_of_questions = ();
    for(my $i = $CONFIG{FIRST_INDEX_OF_ERROR_LABEL} + 1; $i < scalar(@answer_data_column_names); $i++){
	my $error_label = $answer_data_column_names[$i];
	$number_of_questions{$error_label} = 0;
    }

    # 2行目以降は設問毎の正答ならびに誤答データ
    my @answer_data_col = ();
    my $counter = 1;
    while (my $row = $csv->getline ($io)) {
	# コメント行
	next if($row->[0] =~ /^#/);
 
	my %answer_data = ();
	for(my $i = 0; $i < scalar(@answer_data_column_names); $i++){
	    # ラベル (NEGLECT_FOR_LOOP, ..など)
	    my $label = $answer_data_column_names[$i];

	    # 正答又は誤答
	    my $answer = $row->[$i];
	    $answer_data{$label} = Utility::string_to_value($answer);
	    # printf STDERR "DEBUG %s: %s\n", $label, $answer_data{$label};
	}
	$counter++;
	push(@answer_data_col, \%answer_data);
    }
    $csv->eof() or $csv->error_diag();
    close($io);

    foreach my $answer_data_ref (@answer_data_col){
	# 正答
	# my $correct_answer = $answer_data_ref->{answer};
	
	# 設問種別に関する過渡的な措置 
	# (Fri Sep 21 16:43:04 2012)
	if(!defined($answer_data_ref->{type}) || $answer_data_ref->{type} eq ''){
	    $answer_data_ref->{type} = $CONFIG{QUEST_TYPES}->[0];
	}

	for(my $i = $CONFIG{FIRST_INDEX_OF_ERROR_LABEL} + 1; $i < scalar(@answer_data_column_names); $i++){
	    my $error_label = $answer_data_column_names[$i];
	    #
	    next if($error_label eq 'type'); # Fri Sep 21 16:21:14 2012

	    my $error_answer = $answer_data_ref->{$error_label};
	    if(!defined($error_answer)){
		$answer_data_ref->{$error_label} = $CONFIG{NO_ANSWER}; # 未設定
		next;
	    }
	    next if($error_answer eq $CONFIG{NO_ANSWER}); # 無解答
	    # 正答と同じものは無い筈?
	    $number_of_questions{$error_label}++;
	}
    }

    return (\@answer_data_column_names, \@answer_data_col, \%number_of_questions);
}

#######################################
# 設問文
#######################################
# sub quest_string{
#     my ($self, 
sub quest_sentence_html{
    my ($self, $quest) = @_;

    my $code = Code::File->get_by_name($quest->{source});

    # 独自設問文 (Sat Jun  8 20:33:32 2013) 
    if(defined($quest->{sentence})){
	my $sentence_html = $quest->{sentence};
	my $input_form_html = sprintf("<input name=\"%s\">",
				      _q_index_to_q_label($quest->{index}));
	# 置き換え
	$sentence_html =~ s/%%FORM%%/$input_form_html/;
	return $sentence_html;
    }

    if(defined($code) && $code->is_ruby()){
	#
	# Ruby コードの場合
	#
	my ($method_name, $return_variable) = ('', '');
	if(defined($code)){
	    $method_name      = $code->method_name();
	    $return_variable  = $code->p_variable();
	}
	if($quest->{type} eq QUEST_TYPE_INVERSE){
	    # Inverse Trace
	    return sprintf("p %s で出力される値が %s の時，メソッド %s の引数は <input name=\"%s\">である．",
			   $return_variable,
			   Utility::value_to_string($quest->{input}),
			   $method_name,
			   _q_index_to_q_label($quest->{index}));

	}else{
	    # (通常の) Trace

	    # 引数
	    my $value_string;
	    if($quest->{type} eq QUEST_TYPE_TRACE_MORE_THAN_ONE ||
	       $quest->{type} eq QUEST_TYPE_OUTPUT_MORE_THAN_ONE){
		# - 複数個
		$value_string = join(", ", map{Utility::value_to_string($_)} @{$quest->{input}});
	    }else{
		# - 1個
		$value_string = Utility::value_to_string($quest->{input});
	    }

	    # 解答文の一部として問う内容
	    my $end_sentence;
	    if($quest->{type} eq QUEST_TYPE_OUTPUT ||
	       $quest->{type} eq QUEST_TYPE_OUTPUT_MORE_THAN_ONE){
		# 出力を問う
		$end_sentence = "際に表示される値を，順番にカンマ「,」で区切って並べた結果（「1,2,3」のような形式）は";	
	    }elsif($quest->{type} eq QUEST_TYPE_OUTPUT_SIMPLE ||
		   $return_variable ne ''){
		# 従来のパターン
		# - メソッドの最後に p ans があることが前提
		$end_sentence = sprintf("際に p %s で出力される値は", $return_variable);
	    }else{
		# 戻り値・返り値を問う
		$end_sentence = "際の返り値は";
	    }

	    return sprintf("%s(%s)を実行した%s<input name=\"%s\">である．",
			   $method_name,
			   $value_string,
			   $end_sentence,
			   _q_index_to_q_label($quest->{index}));
	}
    }elsif(defined($code) && $code->is_cpp()){
	#
	# C++ 対応 (Thu May 23 07:58:49 2013)
	#
	my $method_name = $code->method_name();

	# 引数
	my $value_string;
	if($quest->{type} eq QUEST_TYPE_TRACE_MORE_THAN_ONE ||
	   $quest->{type} eq QUEST_TYPE_OUTPUT_MORE_THAN_ONE){
	    # - 複数個
	    $value_string = join(", ", map{Utility::value_to_string($_)} @{$quest->{input}});
	}else{
	    # - 1個
	    $value_string = Utility::value_to_string($quest->{input});
	}

	# 設問文
	if($quest->{type} eq QUEST_TYPE_OUTPUT ||
	   $quest->{type} eq QUEST_TYPE_OUTPUT_MORE_THAN_ONE){
	    # 実行結果

	    return sprintf("%s(%s)を実行した際にcoutで出力される値を1 2 3 4のように空白で区切って並べると「<input name=\"%s\">」となる．",
			   $method_name,
			   $value_string,
			   _q_index_to_q_label($quest->{index}));
	}else{
	    # 通常の返り値
	    return sprintf("%s(%s)を実行した際の返り値は「<input name=\"%s\">」である．",
			   $method_name,
			   $value_string,
			   _q_index_to_q_label($quest->{index}));
	}
    }else{
	# それ以外の場合
	# - 「情報(山口和紀先生)」対応のための作り込み  (Fri Jun 29 16:39:50 2012)
	return sprintf("左のプログラムを実行したあとの ans の値は <input name=\"%s\">となる．\n",
		       _q_index_to_q_label($quest->{index}));
    }
}

# $CONFIG{EXAM_DIR}/$self->id()/quest.csv から
# 設問文をカスタマイズする (Sat Jun  8 19:53:03 2013) 
# - %%ANSWER%% を入力フォームに置き換える
# - %%FORM%% を入力値に置き換える
# - Web インタフェース上での設問の順序変更等には対応していない 
#   (Sat Jun  8 20:26:04 2013)
sub read_quest_sentence_file{
    my ($self) = @_;

    my $exam_id = $self->id();

    my $file = sprintf("%s/%s/quest_sentence.csv", $CONFIG{EXAM_DIR}, $exam_id);
    return undef if(! -f $file);

    print STDERR "DEBUG: $file\n";

    my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
    # open(my $io, "<", $file) or die "$file: $!";
    open(my $io, "<", $file) or return undef;

    my @quest_sentence_col = ();

    # 設問番号,設問文
    while (my $row = $csv->getline ($io)) {
	# コメント行
	next if($row->[0] =~ /^#/);

	# 設問番号が無ければ扱わない
	next if($row->[0] !~ /(\d+)/);
	my $quest_id = $1;
	
	$quest_sentence_col[$quest_id] = $row->[1];
    }

    $csv->eof() or $csv->error_diag();
    close($io);

    return \@quest_sentence_col;
}

#######################################
# debug
#######################################
sub _read_time{
    my ($self) = shift;

    return $READ_TIME;
}

#######################################
# ユーティリティ
#######################################

# 文字列を値変換
# - 配列の処理を整理するために用いる
# - ファイル名などの入出力値以外も扱うため，そのまま返す
sub _string_to_value{
    my ($string) = @_;

    $string =~ s/\s//g;
    if($string =~ /^\[(.+)\]$/){
	# $string = $1;
	return eval($string);
	# my @col = eval($string);
	# return \@col;
	# # printf STDERR  "debug: %s\n", $string;
	# my @col = ();
 	# map{push(@col, eval($_))} split(/,/, $string);
	# # print Data::Dumper->Dump(\@col);
	# return \@col;
    }else{
	return $string;
    }
}

sub _q_index_to_q_label{
    my ($q_index) = @_;

    return sprintf("q%03d", $q_index);
}

# q001 -> 1
sub _q_label_to_q_index{
    my ($q_label) = @_;

    if($q_label =~ /^q0*([1-9]\d*)$/){
	return $1;
    }else{
	return;
    }
}

# テキスト出力
sub dump{
    my ($self, $answer_data_column_names_ref, $answer_data_col_ref) = @_;

    # 実行時刻
    printf("# %s\n", POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime()));

    # 見出し
    printf("%s\n", join(',', @{$answer_data_column_names_ref}));

    # 各データ
    foreach my $answer_data (@{$answer_data_col_ref}){
	my @col = 
	    map{
		if(exists($answer_data->{$_})){
		    my $value = Utility::value_to_string($answer_data->{$_});
		    if($value =~ /,/){
			'"' . $value . '"';
		    }else{
			$value;
		    }
		}else{
		    $CONFIG{NO_ANSWER};
		}
	} @{$answer_data_column_names_ref};
	printf("%s\n", join(',', @col));
    }
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;
