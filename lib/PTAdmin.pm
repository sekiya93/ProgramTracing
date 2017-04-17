############################################################
#
# PTAdmin.pm
#
# Time-stamp: <2013-08-27 22:40:25 sekiya>
#
############################################################
# - 管理者向けのインタフェースに特化
package PTAdmin;
use utf8;

use constant{
    CONFIG_DIR        => 'conf',
    #
    FIRST_INDEX_OF_ERROR_LABEL => 3,
};

# ローカルのモジュールを利用するため，ライブラリのパスを
# 明示的に設定
use lib 'lib';

use FileHandle;
use POSIX;
use Data::Dumper;

my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
my %CONFIG;
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

use Exam::File;
use Code::File;
use ExamResponse::File;

use PTHTML;

use ConverterEngine;
my $CONVERTER = ConverterEngine->new();
use Utility;

#######################################
# レスポンス 
#######################################
# - アクセスパス等に応じて，処理を分ける
# - Plack ではこのように作るらしい
# - path に応じて，ページ出力を使い分けるのが流儀の模様
# - 通常は $CONFIG{ADMIN_MODE}, "student" モードに変更する場合は $CONFIG{STUDENT_MODE} を返すことにする
sub response{
    my ($env, $req, $session, $arg, $exam) = @_;

    if(defined($exam)){
	set_exam_data($exam, $arg);
	# print STDERR Data::Dumper->Dump([$exam]);

	# 設問情報
	$arg->{admin_title} = sprintf("%s (id:%s)",
				      $arg->{exam_name},
				      $arg->{exam_id});

	# メニュー
	my $parameters = '?exam_id=' . $arg->{exam_id};
	$arg->{admin_menu} = 
	    admin_menu_html(
		(
		 ["管理",       "admin_management" . $parameters], 
		 ["設問",       "admin_questions"  . $parameters], 
		 ["解答一覧",   "admin_answers"    . $parameters], 
		 ["アンケート", "admin_questionnaire" . $parameters],
		 ["他の試験", "admin"]
		)
	    );

	if($req->path_info() eq '/admin_management'){
	    # 管理者モード > 管理
	    return admin_management($req, $arg, $exam);
	}elsif($req->path_info() eq '/admin_questions'){
	    # 管理者モード > 設問
	    return admin_questions($req, $arg, $exam);
	}elsif($req->path_info() eq '/admin_manage_question'){
	    # 管理者モード > 設問 > 設問管理
	    
	    # 指定された設問
	    my $quest_index = $req->param('quest_index');
	    my $quest = $exam->get_quest_data($quest_index);

	    if(defined($quest)){
		return admin_manage_question($req, $arg, $exam, $quest);
	    }else{
		$arg->{error} = 'No quest! 指定された設問が見付かりません．';
		return admin_questions($req, $arg, $exam);
	    }
	}elsif($req->path_info() eq '/admin_answers'){
	    # 管理者モード > 解答一覧
	    return admin_answers($req, $arg, $exam);
	}elsif($req->path_info() eq '/admin_questionnaire'){
	    # 管理者モード > アンケート
	    return admin_questionnaire($req, $arg, $exam);
	}
    }else{
	# 管理者モードのトップ
	# - 試験($exam) が未定義
	return administrator($req, $arg);
    }
}

#######################################
# 管理者
#######################################
sub is_admin{
    my ($userid) = @_;

    foreach my $admin (@{$CONFIG{ADMINISTRATOR_LIST}}){
	next if($admin ne $userid);
	return 1;
    }
    return 0;
}

#######################################
# 試験問題
#######################################
# 試験情報の設定
# - $arg を Template にも用いる汎用的なデータ保存領域として用いる
# - $arg->{exam_id} に試験のIDが設定されていることが前提
sub set_exam_data{
    my ($exam, $arg) = @_;

    foreach my $key (Exam::File->attribute_names()){
	my $arg_key = 'exam_' . $key;
	$arg->{$arg_key} = PTHTML::escape_text($exam->$key);
    }

    return 1;
}

# 設問
sub set_quest_data{
    my ($exam, $quest, $arg) = @_;

    foreach my $key (Exam::File->quest_attribute_names()){
	my $arg_key = 'quest_' . $key;
	$arg->{$arg_key} = PTHTML::escape_text(Utility::value_to_string($quest->{$key}));
    }

    # 設問種別
    my $type_list = '';
    my $quest_types_ref = Exam::File->quest_types();
    # print STDERR Data::Dumper->Dump([$quest_types_ref]);
    while(my ($quest_type, $quest_type_name) = each(%{$quest_types_ref})){
	# print STDERR "DEBUG: $quest_type, $quest_type_name\n";
	my $selected = '';
	$selected = ' selected' if($quest_type eq $quest->{type});
	$type_list .= 
	    sprintf("<option value=\"%s\"%s>%s</option>",
		    $quest_type, $selected, $quest_type_name);
    }
    $arg->{quest_type_list} = $type_list;

    # 誤答データの HTML化
    my @error_labels = sort keys(%{$CONVERTER->get_converter_data()});
    $arg->{quest_error_labels_html} = '';
    my $counter = 1;
    foreach my $error_label (@error_labels){
	next if($error_label =~ /^(answer|no_answer|unknown)$/);
	$arg->{quest_error_labels_html} .= sprintf(
	    "<tr class=\"by_each_%d\"><th>%s</th><td>%s</td></tr>",
	    ($counter % 2),
	    $error_label,
	    Utility::value_to_string($quest->{$error_label})
	    # $value
	    );
	$counter++;
    }

    # 設問文
    $arg->{quest_sentence} = $exam->quest_sentence_html($quest);    

    return 1;
}

#######################################
# 解答
#######################################
# 解答の取得
# - CGI 変数からの取得 (保存されたファイルからの取得では無い)
# $answer_data{q_label}  = answer
# $answer_data{userid}
# $answer_data{exam_id}
sub get_exam_response{
    my ($req, $arg) = @_;

    my $response = ExamResponse::File->new();
    $response->exam_id(  $arg->{exam_id});
    $response->userid(   $arg->{userid});
    $response->realm(    $arg->{realm});
    $response->fullname( $arg->{fullname});

    foreach my $parameter ($req->parameters()->keys()){
	# 設問に対する解答か
	# print STDERR "parameter: $parameter\n";
	my $q_index = Utility::q_label_to_q_index($parameter);
	next if(!defined($q_index));

 	# 値
 	my $value = $req->parameters()->get($parameter);

	# 処理後の解
	my $answer;
 	if(defined($value) && $value !~ /^\s*$/){
	    # 前後の空白の消去
	    $value =~ s/^\s+//;
	    $value =~ s/\s+$//;

	    if($value =~ /\w\s+\w+/){
		# 空白区切りを配列扱い (Thu May 23 08:39:58 2013)
		$value =~ s/\s+/,/g;
		$value = '[' . $value       if($value !~ /^\s*\[/);
		$value =       $value . ']' if($value !~ /\]\s*$/);
	    }elsif($value =~ /,/){
		# ユーザからの入力に，配列の前後を示す記号 [ ] がなかった場合の対策
		$value = '[' . $value       if($value !~ /^\s*\[/);
		$value =       $value . ']' if($value !~ /\]\s*$/);
	    }
	    $answer = Utility::string_to_value($value);
 	}else{
	    # 無解答
 	    $answer = $CONFIG{NO_ANSWER};
 	}
	print STDERR "get_exam_response value: $value, answer: " . Data::Dumper->Dump([$answer]);
	$response->set_response(
	    $q_index, 
	    $answer,
	    0,
	    []
	    );
    }

    return $response;
}

#######################################
# アンケート
#######################################

# 解答の取得
# $answer_data{q_label}  = answer
# $answer_data{userid}
# $answer_data{exam_id}
sub get_questionnaire_data{
    my ($req, $arg) = @_;

    my %questionnaire_data = ();
    $questionnaire_data{userid}    = $arg->{userid};
    $questionnaire_data{realm}     = $arg->{realm};
    $questionnaire_data{exam_id}   = $arg->{exam_id};
    $questionnaire_data{answer_id} = $arg->{answer_id};
    $questionnaire_data{fullname}  = $arg->{fullname};

    # ユーザからの入力
    my $parameters = $req->parameters();
    foreach my $parameter ($parameters->keys()){
	# 設問に対する解答か
	print STDERR "parameter: $parameter\n";
	my $q_index = Utility::q_label_to_q_index($parameter);
	next if(!defined($q_index));

	# 値
	my $value = $parameters->get($parameter);
	if(defined($value) && $value ne ''){
	    $questionnaire_data{$parameter} = PTHTML::escape_text($value);
	}else{
	    $questionnaire_data{$parameter} = $CONFIG{NO_ANSWER};
	}
    }

    return \%questionnaire_data;
}

# アンケート結果の保存
# - ファイル名
# -- exam_id/exam_id_userid_日時_(ランダムなアルファベット2文字).dat
# -- (解答結果のファイルと対応させておく)
# - ファイル形式
# # exam_id,userid,fullname,解答日時
# index,response
#
# index: 設問番号
# response: 被験者の解答
sub write_questionnaire_data{
    my ($questionnaire_data) = @_;

    my $dir = sprintf("%s/%s", $CONFIG{QUESTIONNAIRE_DIR}, $questionnaire_data->{exam_id});
    mkdir($dir) if(!-d $dir);

    my $date_string = POSIX::strftime("%Y-%m-%d_%H%M_%S", localtime());
    my $file = sprintf("%s/%s.dat",
		       $dir,
		       $questionnaire_data->{answer_id});

    my $fh = FileHandle->new($file, O_WRONLY|O_CREAT);
    die "Cannot open $file." if(!defined($fh));

    $fh->printf("# exam_id: %s, userid: %s, realm: %s, fullname: %s, date: %s\n",
		$questionnaire_data->{exam_id},
		$questionnaire_data->{userid},
		$questionnaire_data->{realm},
		$questionnaire_data->{fullname},
		$date_string);

    foreach my $key (sort(keys(%{$questionnaire_data}))){

	# 設問に対する解答か
	# print STDERR "parameter: $parameter\n";
	my $q_index = Utility::q_label_to_q_index($key);
	next if(!defined($q_index));

	# 回答
	my $response = $questionnaire_data->{$key};
	$fh->printf("%s,\"%s\"\n", 
		    $q_index,
		    $response);
    }

    $fh->close();

    return $questionnaire_data;
}

# 解答一覧の取得
# - $exam_id: 試験ID
# - $answer_order: ソート順(未使用 Tue Sep  4 14:20:27 2012)
# - $number_of_questions_ref: 誤答パターンに一致する設問数
#   {NEGLECT_FOR_LOOP => 8, CHANGE_VARIABLE_IN_LOOP => ?, ...}
sub read_answer_list{
    my ($exam_id, $answer_order, $number_of_questions_ref) = @_;

    my @col = ExamResponse::File->get_list($exam_id);
    foreach my $exam_response (@col){
	$exam_response->set_error_patterns($number_of_questions_ref);
    }

    if($answer_order eq 'userid'){
	return sort {$a->userid() cmp $b->userid()} @col;
    }else{
    	return sort {$a->date() cmp $b->date()} @col;
    }
}

#######################################
# ページごとの処理
#######################################
# トップページ
sub administrator {
    my ($req, $arg) = @_;
    

    # テスト一覧の読み込み
    my @exams = Exam::File->exam_list();
    $arg->{exam_list_for_answers} = '';

    foreach my $exam (sort{$a->id() cmp $b->id()} @exams){
	$arg->{exam_list_for_answers} .= 
	    sprintf("<li><a href=\"admin_answers?exam_id=%s\">%s (id:%s, %s 更新)</a></li>\n",
		    $exam->id(),
		    $exam->name(),
		    $exam->id(),
		    $exam->modified()
	    );
    }

    # メニュー
    $arg->{admin_menu} = admin_menu_html( (["試験管理", "admin"], ["新規試験", ""], ["設問管理", ""]));

    # ページ出力のための準備
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(PTHTML::render('administrator.html', $arg));
    $res->finalize();
}
                                                                                # 管理者モード: 設問
# - 入力
# -- $arg->{exam_id} が指定されることが前提?
sub admin_questions{
    my ($req, $arg, $exam) = @_;

    if(defined($req->param('task'))){
	if($req->param('task') eq 'add'){
	    # 設問の追加
	    $exam->add_quest_data();
	}elsif($req->param('task') eq 'delete' && $req->param('quest_index') =~ /(\d+)/){
	    # 設問の削除
	    $exam->delete_quest_data($1);
	}elsif($req->param('task') eq 'move_forward' && $req->param('quest_index') =~ /(\d+)/){
	    # 設問の順序変更
	    $exam->move_forward_quest_data($1);
	}
    }

    # 指定された試験の読み込み
    my ($answer_data_column_names_ref, $answer_data_col_ref, $number_of_questions_ref) = $exam->read_exam_answer_file();
    
    # (Template でも利用される)
    $arg->{exam_html} = '';

    my $previous_code = '';
    my $code_string   = '';
	
    foreach my $quest (@{$answer_data_col_ref}){

	# ソースコード
	if($previous_code eq $quest->{source}){ 
	    $code_string = '(同上)';
	}else{
	    $previous_code = $quest->{source};
	    my $code = Code::File->get_by_name($quest->{source});
	    if(defined($code)){
		$code_string      = PTHTML::escape_text($code->code());
	    }
	}

	my $sentence_html = $exam->quest_sentence_html($quest);
	$arg->{exam_html} .= sprintf("<tr><th>問 %s</th><td><a name=\"quest%s\">%s<br><pre class=\"screen\">%s</pre></a></td><td>%s</td><td><a href=\"admin_manage_question?exam_id=%s&quest_index=%s\">編集</a></td><td><a href=\"admin_questions?exam_id=%s&task=move_forward&quest_index=%s#quest%s\">上へ</a></td></tr>\n",
				     $quest->{index},
				     $quest->{index},
				     $quest->{source},
				     $code_string,
				     $sentence_html,
				     $exam->id(),
				     $quest->{index},
				     $exam->id(),
				     $quest->{index},
				     ($quest->{index} - 1));
    }




    # ページ出力のための準備 
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(PTHTML::render('admin_questions.html', $arg));
    $res->finalize();
}

# 管理者モード: 解答一覧
# - 入力
# -- $arg->{exam_id} が指定されることが前提?
sub admin_answers{
    my ($req, $arg, $exam) = @_;

    # 指定された試験の読み込み
    my ($answer_data_column_names_ref, $answer_data_col_ref, $number_of_questions_ref) = $exam->read_exam_answer_file();

    # 設問数
    my $number_of_question = @{$answer_data_col_ref};

    # ヘッダの追加情報
    $arg->{answer_item_header} = 
    # 解答及び回答の一覧
    my $answer_order = $CONFIG{DEFAULT_ANSWER_ORDER};
    $answer_order = $req->param('answer_order') if(defined($req->param('answer_order')));
    my @answer_list = read_answer_list($arg->{exam_id}, $answer_order, $number_of_questions_ref, $arg);
    $arg->{answer_list} = '';
  
    my $counter = 0;

    foreach my $user_answer_data (@answer_list){
	# (項番) ユーザ名, 氏名, 得点, 解答時刻, (誤答パターン)
	$arg->{answer_list} .= sprintf(
	    "<tr class=\"by_each_%d\"><th>%d</th><td>%s</td><td>%s</td><td style=\"text-align:right;\">%d</td><td>%s</td><td>%s</td></tr>\n",
	    ($counter % 2),
	    $counter + 1,
	    $user_answer_data->userid(),
	    $user_answer_data->fullname(),
	    $user_answer_data->score(),
	    $user_answer_data->date(),
	    join(", ", @{$user_answer_data->user_error_patterns()}),
	    );
	$counter++;
    }
    $arg->{number_of_answers} = $counter;

    # ページ出力のための準備
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(PTHTML::render('admin_answers.html', $arg));
    $res->finalize();
}

# 管理者モード: 管理
# - 基本情報の更新
sub admin_management{
    my ($req, $arg, $exam) = @_;

    if(!defined($exam)){
	die "No exam (id:" . $arg->{exam_id} . ")!";
    }

    if($req->param('task') eq 'modify'){
	my %value_hash = ();
	foreach my $key (Exam::File->attribute_names()){
	    next if($key eq 'id'); # id は更新しない
	    my $arg_key = 'exam_' . $key;
	    $value_hash{$key} = $req->param($arg_key);
	}
	# データの更新
	$exam->modify_attributes(\%value_hash);
	$exam->save();

	# 表示用のデータの更新
	set_exam_data($exam, $arg);
    }

    # ページ出力のための準備
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(PTHTML::render('admin_management.html', $arg));
    $res->finalize();
}

# 管理者モード: 個々の設問の管理
# - 入力値の変更
# - (ソースの変更)
sub admin_manage_question{
    my ($req, $arg, $exam, $quest) = @_;

    if(defined($req->param('task')) &&
       $req->param('task') eq 'modify'){
	foreach my $key (Exam::File->quest_attribute_names()){
	    my $arg_key = 'quest_' . $key;
	    # 入力値のみ修正 (Mon Apr 22 13:25:57 2013)
	    if($arg_key eq 'quest_input'){
		$quest->{$key} = Utility::string_to_value($req->param($arg_key));
	    }else{
		$quest->{$key} = $req->param($arg_key);
	    }
	}
	# データ更新
	$quest = $CONVERTER->evaluate_answer_item($quest);
	$exam->set_quest_data($quest);
    }

    # ソース一覧
    my $name_list = '';
    my $code_list = '';
    my %code_hash = %{Code::File->code_list()};
    my $target_code;
    my ($method_name, $return_variable) = ('', '');
    foreach my $code_name (sort(keys(%code_hash))){
	my $code = $code_hash{$code_name};
	my $selected = '';
	my $display = 'none';
	if($code_name eq $quest->{source}){
	    $selected = ' selected';
	    $display = 'block';
	    #
	    $target_code     = $code;
	    $method_name     = $target_code->method_name();
	    $return_variable = $target_code->p_variable();
	}
	$name_list .= 
	    sprintf("<option value=\"%s\"%s>%s</option>",
		    $code_name, $selected, $code_name);
	$code_list .= 
	    sprintf("<div id=\"code_string_area_%s\" style=\"display:%s\">%s</div>",
		    $code_name, $display, PTHTML::escape_text($code->code()));
    }

    $arg->{quest_source_list} = $name_list;
    $arg->{quest_code_string} = $code_list;

    # HTML化
    set_quest_data($exam, $quest, $arg);

    # ページ出力のための準備
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(PTHTML::render('admin_manage_question.html', $arg));
    $res->finalize();
}

############################################################
# 管理者インタフェース用メニュー
############################################################
# メニューの作成
# - 入力: ([label1, url1], [label2, url2], ...)
# - 出力: (HTML)
sub admin_menu_html{
    my @links = @_;
    
    my $html = '';
    # print STDERR Data::Dumper->Dump(\@links);
    foreach my $link (@links){

	if(defined($link->[1])){
	    $html .= sprintf("<li><a href=\"%s\" class=\"admin_menu\">%s</a></li>\n", $link->[1], $link->[0]);
	}else{
	    $html .= sprintf("<li>%s</li>\n", $link->[0]);
	}
    }

    return $html;
}

1;
