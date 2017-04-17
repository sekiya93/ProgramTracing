############################################################
#
# Tracing 問題用 Web アプリケーション (2012-04-16)
#
# Time-stamp: <2014-06-17 09:46:41 sekiya>
#
############################################################
use strict;
use warnings;
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
use Text::CSV;
use POSIX;
use Data::Dumper;
use File::Copy;

my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
my %CONFIG;
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

use Template;
my $TEMPLATE_CONFIG = {INCLUDE_PATH => $CONFIG{TEMPLATE_DIR}};

use Plack::Builder;
use Plack::Request;
use Plack::Session;
use Plack::Session::State::Cookie;
use Plack::Session::Store::File;

use PTAuth;
use PTAdmin;
use PTLog;
my $PTLOG = PTLog->init();

use BLTI;

use Mail::IMAPClient;
our $DB = PTDB->new(
    {
	connect_info => ['DBI:Pg:dbname=' . $CONFIG{DBNAME} . ';host=' . $CONFIG{DBHOST} . ';', $CONFIG{DBUSER}]
    });

my $ACCESS_LOG = $CONFIG{LOG_DIR} .  POSIX::strftime("/access_log.%Y-%m-%d", localtime());

use CFIVE::CfiveUser;
use Exam::File;
use Code::File;
use ExamResponse::File;

use ConverterEngine;
my $CONVERTER = ConverterEngine->new();
use Utility;

#######################################
# レスポンス 
#######################################
# - アクセスパス等に応じて，処理を分ける
# - Plack ではこのように作るらしい
# - path に応じて，ページ出力を使い分けるのが流儀の模様
my $APP = sub {
    my $env     = shift;
    my $req     = Plack::Request->new($env);
    my $session = Plack::Session->new($req->env);
    
    print STDERR Data::Dumper->Dump([$req]);
    print STDERR Data::Dumper->Dump([$req->parameters]);
    
    # client ip
    # - Apache mod_proxy 経由で利用していることが前提
    # - リバースプロキシのリクエストヘッダから読み取る
    # - See http://httpd.apache.org/docs/2.2/ja/mod/mod_proxy.html
    $session->set('client_ip', $req->header('X-Forwarded-For'));
    
    # LTI対応
    my $isBlti = BLTI::is_blti_req($req, $session);
    if($isBlti && !BLTI::blti_req($req, $session)){
    	return not_authorized($req, {error => '署名が不正です'});
    }
    
    if($req->path_info() eq '/login'){
	# ログイン
	return login($req, $session);
    }elsif($req->path_info() eq '/logout'){
	# ログアウト
	return logout($req, $session);
    }else{
	# その他のページ

	# 以下は，すべてのページでの共通処理
	my $arg = generate_arg($req, $session);
	# debug (Mon Sep 17 22:48:26 2012)
	print STDERR Data::Dumper->Dump([$arg]);

	if($req->path_info() eq '/tool_config.xml'){
		return BLTI::tool_config($req, $arg);
	}
	
	# - ログインしていない場合
	return not_authorized($req, {error => 'ログインしていません．'}) if(!$session->get('verified'));
	
	my $exam = Exam::File->get_by_id($arg->{exam_id});
	$arg->{exam_name} = escape_text($exam->name()) if(defined($exam));
	printf STDERR "path: %s, mode: %s(%d)\n", $req->path_info(), $arg->{mode}, $arg->{is_admin};

	if($isBlti){
		if($req->path_info() eq '/launch/init'){
			return BLTI::list_exam_rs($req, $arg);
		}
	}
	
	if($arg->{is_admin} && $arg->{mode} eq $CONFIG{ADMIN_MODE}){
	    #
	    # 管理者モード
	    #
	    if($req->path_info() eq '/student' && $arg->{is_admin}){
		# 管理者モード -> 学生モード
		$session->set('mode', $CONFIG{STUDENT_MODE});
		return list_exam($req, $arg);
	    }else{
		# 通常の管理者モード
		return PTAdmin::response($env, $req, $session, $arg, $exam);
	    }
	}else{
	    # 
	    # 学生モード
	    #
	    if($req->path_info() eq '/take_exam'){
		# 指定された試験を受験
		return take_exam($req, $arg, $exam, $session);
	    }elsif($req->path_info() eq '/answer_exam'){
		# 指定された試験に解答，採点結果を表示
		return answer_exam($req, $arg, $exam, $session);
	    }elsif($req->path_info() eq '/questionnaire'){
		# 指定された試験の採点結果に対してアンケートを入力
		return questionnaire($req, $arg, $exam, $session);
		}elsif($req->path_info() eq '/make_exam'){
		#試験問題作成トップページ
		return make_exam($req, $arg, $exam, $session);
		}elsif($req->path_info() eq '/create_exam'){
		#試験作成
		return create_exam($req, $arg, $exam, $session);
	    }elsif($req->path_info() eq '/admin' && $arg->{is_admin}){
		# 学生モード -> 管理者モード
		$session->set('mode', $CONFIG{ADMIN_MODE});
		return administrator($req, $arg);
	    }else{
		# 特に指定がなければ，試験一覧を表示
		return list_exam($req, $arg);
	    }
	}
    }
};

#######################################
# 管理者
#######################################
sub is_admin{
    my ($userid, $session) = @_;
	if(index($session->get('roles'), 'Instructor') != -1){
		return 1;
	}
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
	$arg->{$arg_key} = escape_text($exam->$key);
    }

    return 1;
}

# 設問
sub set_quest_data{
    my ($exam, $quest, $arg) = @_;

    foreach my $key (Exam::File->quest_attribute_names()){
	my $arg_key = 'quest_' . $key;
	$arg->{$arg_key} = escape_text(Utility::value_to_string($quest->{$key}));
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
	print STDERR "parameter: $parameter\n";
	my $q_index = q_label_to_q_index($parameter);
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
	my $q_index = q_label_to_q_index($parameter);
	next if(!defined($q_index));

	# 値
	my $value = $parameters->get($parameter);
	if(defined($value) && $value ne ''){
	    $questionnaire_data{$parameter} = escape_text($value);
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
	my $q_index = q_label_to_q_index($key);
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
# ユーティリティ
#######################################
sub escape_text{
    my $s = shift;

    $s =~ s|\&|&amp;|g;
    $s =~ s|<|&lt;|g;
    $s =~ s|>|&gt;|g;
    $s =~ s|\"|&quot;|g;
    $s =~ s|\r\n|\n|g;
    $s =~ s|\r|\n|g;
    $s =~ s|\n|<br>|g;

    return $s;
}

#######################################
# ページごとの処理
#######################################
# ログイン
sub login {
    my ($req, $session) = @_;

    # ページ出力などの際に用いる最小限の引数みたいなものか
    my $arg = {
	session_id => $session->id(),
    };
    my $userid   = $req->param('userid');
    my $password = $req->param('password');

    # 認証
    if(PTAuth::auth($userid, $password, $arg)){
	# 認証が通った場合 
	$session->set('verified', 1);
	$session->set('userid',   $userid);
	$session->set('realm',    $arg->{realm});
	$session->set('mode',     $CONFIG{DEFAULT_MODE});

	# すべてのページでの共通処理
	$arg->{userid}     = $userid;
	$arg->{fullname}   = PTAuth::get_fullname($arg);
	$arg->{title}      = $CONFIG{"PAGE_TITLE_" . $session->get('realm')}; 
	$arg->{admin}      = $CONFIG{"PAGE_ADMIN_" . $session->get('realm')};
	$arg->{code_title} = $CONFIG{"PAGE_CODE_TITLE_" . $session->get('realm')};
	$arg->{is_admin}   = is_admin($arg->{userid}, $session);
	
	# log (Fri Apr  5 09:54:58 2013)
	$PTLOG->info("Login succeeded for $userid.", $session);

	# ダイレクトリンク対応
	my $exam;
	if(defined($req->param('exam_id'))){
	    $arg = generate_arg($req, $session);
	    $exam = Exam::File->get_by_id($arg->{exam_id});
	}
	if(defined($exam)){
	    # - 試験を受験
	    $arg->{exam_name} = escape_text($exam->name());
	    take_exam($req, $arg, $exam, $session);
	}else{
	    # - テスト一覧を生成する
	    list_exam($req, $arg);
	}
    }else{
	# 認証が通らない場合 
	$arg->{error} = 'userid 又はパスワードが間違っています．';

	# log (Fri Apr  5 09:54:58 2013)
	$PTLOG->error("Login failed for $userid.", $session);

	not_authorized($req, $arg);
    }
}

# ログアウト
sub logout {
    my ($req, $session) = @_;

    # ページ出力などの際に用いる最小限の引数みたいなものか
    my $arg = {
# 	session_id => $session->id(),
# 	userid     => $req->param('userid'),
	session_id => '',
	userid     => '',
	info       => 'ログアウトしました．',
    };
    $session->expire();

    # log (Fri Apr  5 09:54:58 2013)
    $PTLOG->info("Logout.", $session);
    
    # ページ出力
    not_authorized($req, $arg);
}

# ログイン中でない場合
sub not_authorized {
    my ($req, $arg) = @_;

    if(defined($req->param('exam_id'))){
	$arg->{exam_id} = $req->param('exam_id');
    }

    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('login.html', $arg));
    $res->finalize();
}

# 指定された試験を受験
# - 答案を表示
sub take_exam {
    my ($req, $arg, $exam, $session) = @_;

    # 非公開の試験は受験できない
    if($arg->{realm} eq $CONFIG{REALM_LOCAL} || $arg->{realm} eq $CONFIG{REALM_ECCS} && $exam->is_open_to_eccs() ||
       $arg->{realm} eq $CONFIG{REALM_GAKUGEI} && $exam->is_open_to_gakugei()
	){

	# 指定された試験の読み込み
	my ($answer_data_column_names_ref, $answer_data_col_ref) = 
	$exam->read_exam_answer_file();

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
		    $code_string      = escape_text($code->code());
		}
	    }

	    my $sentence_html = $exam->quest_sentence_html($quest);
	    $arg->{exam_html} .= sprintf("<tr><th>問 %s</th><td><pre class=\"screen\">%s</pre></td><td>%s</td></tr>\n",
					 $quest->{index},
					 $code_string,
					 $sentence_html,
					 $exam->id(),
					 $quest->{index});
	}
	
	# log (Fri Apr  5 11:00:59 2013)
	$PTLOG->info("Take exam (id:" . $exam->id() . ").", $session);

    }else{
	$arg->{error} = 'この試験は公開されていません．';
    }

    # ページ出力のための準備
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('take_exam.html', $arg));
    $res->finalize();
}

# 指定された試験に解答，採点結果を表示
# - どのように考えたかを入力してもらう
sub answer_exam {
    my ($req, $arg, $exam, $session) = @_;

    if(!defined($exam)){
	die "No exam (id:" . $arg->{exam_id} . ")!";
    }

    # 指定された試験の読み込み
    my ($exam_answer_data_column_names_ref, $exam_answer_data_col_ref, $number_of_questions_ref) = $exam->read_exam_answer_file();

    # 被験者の入力
    my $exam_response = get_exam_response($req, $arg);
    
    # debug (Sun Sep 23 13:14:01 2012)
#     printf(STDERR "answer_data: %s\n", Data::Dumper->Dump([$exam_response]));
#     printf(STDERR "exam_answer_datanswer_data: %s\n", Data::Dumper->Dump([$exam_response]));

    # 判定結果
    my ($result_data, $correct_data) = 
	$CONVERTER->set_result_of_exam_response($exam_response, $exam_answer_data_col_ref);

    # ファイル出力
    $exam_response->save($session);
    # write_answer_data($user_answer_data, $result_data, $correct_data);

    # (Template でも利用される)
    $arg->{answer_id}   = $exam_response->answer_id();
    $arg->{answer_html} = '';

    # 誤答パターン
    my $converter_data;
    $arg->{show_error_pattern} = $CONFIG{SHOW_ERROR_PATTERN_BEFORE};
    if($arg->{show_error_pattern}){
	$converter_data = $CONVERTER->get_converter_data();
    }

    my $previous_code = '';
    my ($prev_method_name, $prev_return_variable);
    my $code_string = '';
    my $count = 0;
    my $count_correct = 0;

    foreach my $quest (@{$exam_answer_data_col_ref}){
	$count++;
	# ソースコード
	if($previous_code eq $quest->{source}){ 
	    $code_string = '(同上)';
	}else{
	    $previous_code = $quest->{source};
	    my $code = Code::File->get_by_name($quest->{source});
	    if(defined($code)){
		$code_string      = escape_text($code->code());
	    }
	}

	# 設問文
	my $sentence_html = $exam->quest_sentence_html($quest);

	# 設問情報
	my $q_index = $quest->{index};

	my $each_response = $exam_response->get_response($q_index);
	print STDERR Data::Dumper->Dump([$each_response]);
	my $q_label = q_index_to_q_label($q_index);

	# 背景色
	my $bg_color;
	if($each_response->{result}){
	    $bg_color = $CONFIG{BG_COLOR_CORRECT};
	    $count_correct++;
	}else{
	    $bg_color = $CONFIG{BG_COLOR_INCORRECT};
	}
	
	# 解答
	my $user_answer = Utility::value_to_string($each_response->{user_answer});
	# 正答
	my $correct_answer = Utility::value_to_string($quest->{answer});

	# 誤答パターン
	my $error_pattern_html = '';
	if($arg->{show_error_pattern}){
	    # - 表示する場合
	    my @pattern_col = ();
	    foreach my $error_pattern (@{$each_response->{error_label}}){
		next if(!exists($converter_data->{$error_pattern}));
		push(@pattern_col, $converter_data->{$error_pattern}->{description});
	    }
	    $error_pattern_html = "<td>" . join("或いは", @pattern_col) . "</td>";
	}

	$arg->{answer_html} .= sprintf("<tr style=\"background:%s;\"><th>問 %s</th><td><pre class=\"screen\">%s</pre></td><td>%s</td><td>%s</td><td>%s</td><td><textarea cols=\"30\" rows=\"5\" name=\"%s\"></textarea></td>%s</tr>\n",
				       $bg_color,
				       $q_index,
				       $code_string,
				       $sentence_html,
				       $user_answer,
				       $correct_answer,
				       $q_label,
				       $error_pattern_html);
    }

    # log (Fri Apr  5 11:00:59 2013)
    $PTLOG->info("Answer exam (id:" . $exam->id() . ").", $session);
    
    my $grade = 1.0 * $count_correct / $count;
    BLTI::send_result($req, $session, $grade);

    # ページ出力のための準備
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('answer_exam.html', $arg));
    $res->finalize();
}

# アンケート
sub questionnaire{
    my ($req, $arg, $exam, $session) = @_;

    # answer_id 
    $arg->{answer_id} = $req->param('answer_id');

    # 指定された試験の読み込み
    my ($exam_answer_data_column_names_ref, $exam_answer_data_col_ref, $number_of_questions_ref) = 
	$exam->read_exam_answer_file();

    # エラーラベル
    my @error_label_col = @{$exam_answer_data_column_names_ref}[FIRST_INDEX_OF_ERROR_LABEL .. (scalar(@{$exam_answer_data_column_names_ref}) - 1)];

    # 被験者の入力
    my $questionnaire_data = get_questionnaire_data($req, $arg);

    # ファイル出力
    write_questionnaire_data($questionnaire_data);

    # 解答の読込み
    my $exam_response = ExamResponse::File->get($arg->{exam_id}, $arg->{answer_id});

    # 判定結果
    my ($result_data, $correct_data) = 
	$CONVERTER->set_result_of_exam_response($exam_response, $exam_answer_data_col_ref);

    # 画面出力
    $arg->{questionnaire_html} = '';

    # 誤答パターン
    my $converter_data;
    $arg->{show_error_pattern} = $CONFIG{SHOW_ERROR_PATTERN_AFTER};
    if($arg->{show_error_pattern}){
	$converter_data = $CONVERTER->get_converter_data();
    }

    my $previous_code = '';
    my ($prev_method_name, $prev_return_variable);
    my $code_string = '';

    foreach my $quest (@{$exam_answer_data_col_ref}){

	# ソースコード
	if($previous_code eq $quest->{source}){ 
	    $code_string = '(同上)';
	}else{
	    $previous_code = $quest->{source};
	    my $code = Code::File->get_by_name($quest->{source});
	    if(defined($code)){
		$code_string      = escape_text($code->code());
	    }
	}

	# 設問文
	my $sentence_html = $exam->quest_sentence_html($quest);

	# 設問情報
	my $q_index = $quest->{index};

	my $each_response = $exam_response->get_response($q_index);
	print STDERR Data::Dumper->Dump([$each_response]);
	my $q_label = q_index_to_q_label($q_index);

	# 背景色
	my $bg_color;
	if($each_response->{result}){
	    $bg_color = $CONFIG{BG_COLOR_CORRECT};
	}else{
	    $bg_color = $CONFIG{BG_COLOR_INCORRECT};
	}
	
	# 解答
	my $user_answer        = Utility::value_to_string($each_response->{user_answer});
	# 正答
	my $correct_answer     = Utility::value_to_string($quest->{answer});
	# アンケート回答
	my $each_questionnaire_html = escape_text($questionnaire_data->{$q_label});
	utf8::decode $each_questionnaire_html;

	# 誤答パターン
	my $error_pattern_html = '';
	if($arg->{show_error_pattern}){
	    # - 表示する場合
	    my @pattern_col = ();
	    foreach my $error_pattern (@{$each_response->{error_label}}){
		next if(!exists($converter_data->{$error_pattern}));
		push(@pattern_col, $converter_data->{$error_pattern}->{description});
	    }
	    $error_pattern_html = "<td>" . join("或いは", @pattern_col) . "</td>";
	}

	$arg->{questionnaire_html} .= sprintf("<tr style=\"background:%s;\"><th>問 %s</th><td><pre class=\"screen\">%s</pre></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td>%s</tr>\n",
				       $bg_color,
				       $q_index,
				       $code_string,
				       $sentence_html,
				       $user_answer,
				       $correct_answer,
				       $each_questionnaire_html,
				       $error_pattern_html);
    }

    # log (Fri Apr  5 11:14:09 2013)
    $PTLOG->info("Questionnaire exam (id:" . $exam->id() . ").", $session);

    # ページ出力のための準備
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('questionnaire.html', $arg));
    $res->finalize();
}

# テスト一覧
# - 学生向け
sub list_exam {
    my ($req, $arg) = @_;

    # テスト一覧の読み込み
    my @exams = Exam::File->exam_list();
    $arg->{exam_list} = '';

    foreach my $exam (sort{$a->id() cmp $b->id()} @exams){
		# 非公開の試験はスキップ
		#next unless($arg->{realm} eq $CONFIG{REALM_ECCS} && $exam->is_open_to_eccs() ||
		#    $arg->{realm} eq $CONFIG{REALM_GAKUGEI} && $exam->is_open_to_gakugei());
		# next if(! $exam->is_open());
		$arg->{exam_list} .= 
	    sprintf("<li><a href=\"take_exam?exam_id=%s\">%s (id:%s, %s 更新)</a></li>\n",
		    $exam->id(),
		    $exam->name(),
		    $exam->id(),
		    $exam->modified()
	    );
    }

    # ページ出力のための準備
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('list.html', $arg));
    $res->finalize();
}

########################################################################
# 管理者

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
    $res->body(render('administrator.html', $arg));
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
		$code_string      = escape_text($code->code());
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
    $res->body(render('admin_questions.html', $arg));
    $res->finalize();
}

# 管理者モード: 解答一覧
# - 入力
# -- $arg->{exam_id} が指定されることが前提?
sub admin_answers{
    my ($req, $arg, $exam) = @_;

    # 指定された試験の読み込み
    my ($answer_data_column_names_ref, $answer_data_col_ref, $number_of_questions_ref) = $exam->read_exam_answer_file();

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
    $res->body(render('admin_answers.html', $arg));
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
    $res->body(render('admin_management.html', $arg));
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
		    $code_name, $display, escape_text($code->code()));
    }

    $arg->{quest_source_list} = $name_list;
    $arg->{quest_code_string} = $code_list;

    # HTML化
    set_quest_data($exam, $quest, $arg);

    # ページ出力のための準備
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('admin_manage_question.html', $arg));
    $res->finalize();
}

# 管理者インタフェース用メニューの作成
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

# 作成中
sub not_yet {
    my ($req, $arg) = @_;
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('not_yet.html', $arg));
    $res->finalize();
}

# ページ出力
sub render{
    my ($name, $arg) = @_;
    #my $tt = Template->new($TEMPLATE_CONFIG);
    my $tt = Template->new(INCLUDE_PATH => $CONFIG{TEMPLATE_DIR}, UNICODE  => 1, ENCODING => 'utf-8'); # TODO confirm
    my $out;
    $tt->process( $name, $arg, \$out );
    utf8::encode $out if utf8::is_utf8 $out; # TODO remove?
    return $out;
}

# 引数の処理
# - {key1 => value1, key2 => value2, ...} はあくまでも簡易的な記法
# -- (いかにも Perl)
# - いずれかの key や value が undef だと，対応関係が崩れる
sub generate_arg{
    my ($req, $session) = @_;

    my $arg = {
	session_id => $session->id(),
	userid     => $session->get('userid'),
	realm      => $session->get('realm'),
	username => $session->get('username')
    };
    if(defined($arg->{realm})){
	my $r = uc($arg->{realm});
	my $code_title = $CONFIG{"PAGE_CODE_TITLE_" . $r};
	utf8::decode $code_title;
	$arg->{title}      =  $CONFIG{"PAGE_TITLE_" . $r};
	$arg->{admin}      =  $CONFIG{"PAGE_ADMIN_" . $r};
	$arg->{code_title} =  $code_title;
    }
    if(defined($session->get('mode'))){
	$arg->{mode} = $session->get('mode');
    }
    if(defined($req->param('exam_id'))){
	$arg->{exam_id} = $req->param('exam_id');
    }

    $arg->{fullname} = PTAuth::get_fullname($arg);
    $arg->{is_admin} = is_admin($arg->{userid}, $session);

    return $arg;
}

#試験問題作成トップページ
sub make_exam {
	my ($req, $arg, $exam, $session) = @_;
	my $arg = {
		session_id => $session->id(),
		userid     => $session->get('userid'),
		realm      => $session->get('realm')
	};
	# ページ出力のための準備
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('make_exam.html', $arg));
    $res->finalize();
}
#試験登録
sub create_exam {
	my ($req, $arg, $exam, $session) = @_;
	my $arg = {
		session_id => $session->id(),
		userid     => $session->get('userid'),
		realm      => $session->get('realm')
	};
	my $upload = $req->uploads;
	my $file = $upload->{exam_file};
	
	if (defined($file) && $file->filename ne "") {
		#ファイル存在
		print STDERR "fileName:". $CONFIG{TOP_DIR}. "/" .$CONFIG{RUBY_CODE_DIR}."/".$file->filename ."\n";
		#ファイルをexam/ruby_codeにコピー
		copy($file->path, $CONFIG{TOP_DIR}. "/" .$CONFIG{RUBY_CODE_DIR}."/".$file->filename);
		
		# generate_convertered_codesを実行
		my $command = "perl ".$CONFIG{TOP_DIR}."/".$CONFIG{TOOLS_DIR}."/generate_convetered_codes.pl " .$CONFIG{TOP_DIR}."/".$CONFIG{RUBY_CODE_DIR}."/".$file->filename;
		print STDERR "command:" . $command."\n";
		my $return_value = system $command;
	}
	# ページ出力のための準備
    my $res = $req->new_response(200);
    $res->redirect('make_exam?id='.$arg->{userid});
    $res->finalize();
}

########################################################################
# 基本情報
########################################################################
builder {
    # Debug
    # - 環境変数や Memory 利用状況などを確認可能
    # - 運用時にはコメントアウト
    # enable 'Debug';  

    # AccessLog
    enable_if { $_[0]->{REMOTE_ADDR} eq '127.0.0.1' } "Plack::Middleware::ReverseProxy";
    my $logfh;
    open $logfh, ">>", $ACCESS_LOG or die $!;
    enable 'AccessLog', logger => sub {print $logfh @_};
    #
    enable "Plack::Middleware::Static",
    path => qr/static/,
    root => '.';
    enable 'Session',
    store => Plack::Session::Store::File->new(
	dir => 'tracing/sessions'
        );
    enable "Plack::Middleware::REPL";
    enable "Plack::Middleware::Lint";
    $APP;
};
