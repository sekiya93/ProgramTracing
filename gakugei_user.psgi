############################################################
#
# 東京学芸大学のユーザ向け
#
# Time-stamp: <2014-05-11 13:53:45 sekiya>
#
############################################################
# - ユーザ登録機能のみ

use strict;
use warnings;

use constant{
    CONFIG_DIR        => 'conf',
    #CONFIG_DIR        => '/usr/local/plack/tracing/conf',
    #
    LOG_FILE_BASENAME => 'gakugei_user_log',
    #
    NUMBER_OF_ALPHABET        => 26,
    ASCII_CODE_OF_LOWERCASE_A => 97,
    KEY_LENGTH                => 5,
    #
    LENGTH_OF_PASSWORD => 6,
};

# ローカルのモジュールを利用するため，ライブラリのパスを
# 明示的に設定
use lib '/usr/local/plack/tracing/lib';

use FileHandle;
use Text::CSV;
use POSIX;
use Config::Simple;
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use Log::Dispatch::FileRotate;
use Net::SMTP::SSL;
# 内部で Authen::SASL を利用しているので，インストールが必要

sub my_mkdir($);

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

# my $ACCESS_LOG = $CONFIG{LOG_DIR} .  POSIX::strftime("/gakugei_user_log.%Y-%m-%d", localtime());
my $LOGGER = Log::Dispatch::FileRotate->new(
    name        => 'gakugei_user',
    min_level   => 'debug',
    filename    => $CONFIG{LOG_DIR} . "/gakugei_access_log",
    mode        => 'append',
    # TZ          => 'JST',
    DatePattern => 'yyyy-MM-dd',
    );

use PTAuth;
use PTDB;
our $DB = PTDB->new(
    {
	connect_info => ['DBI:Pg:dbname=' . $CONFIG{DBNAME} . ';host=' . $CONFIG{DBHOST} . ';', $CONFIG{DBUSER}]
    });

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
    
    # client ip
    # - Apache mod_proxy 経由で利用していることが前提
    # - リバースプロキシのリクエストヘッダから読み取る
    # - See http://httpd.apache.org/docs/2.2/ja/mod/mod_proxy.html
    $session->set('client_ip', $req->header('X-Forwarded-For'));

    # ページ出力などの際に用いる最小限の引数みたいなものか
    my $arg = {
	session_id => $session->id(),
	common_url => $CONFIG{GAKUGEI_COMMON_URL},
	hostname   => $CONFIG{HOSTNAME}
    };

    if($req->path_info() eq '/account'){
	# /account
	# - アカウント情報(ユーザID, メールアドレス, 氏名)の入力を求める
	return account_page($req, $session, $arg);	
    }elsif($req->path_info() eq '/account_confirm'){
	# /account_confirm
	# - 入力されたアカウント情報の確認
	# - メール送信
	return account_confirm_page($req, $session, $arg);
    }elsif($req->path_info() eq '/account_register'){
	# /account_register
	# - アカウント情報の登録
	return account_register_page($req, $session, $arg);
    }elsif($req->path_info() eq '/reset'){
	# /reset 
	# - パスワードのリセット用の画面を表示
	# - 事前に登録したメールアドレスの入力を求める
	return reset_page($req, $session, $arg);
    }elsif($req->path_info() eq '/reset_confirm'){
	# /reset_confirm
	# - 入力されたメールアドレスが登録済みかどうかをチェック
	# - ユーザID,メールアドレス,リセット用の一時キーを保存
	# - パスワードリセット用のメールを送信
	return reset_confirm_page($req, $session, $arg);
    }elsif($req->path_info() eq '/reset_execution'){
	# /reset_execution
	# - パスワードリセット用のメールのクリックで，パスワードのリセットを実行
	# - (二度押されないように一時キーを消去)
	# - リセットされたことをメールで送信
	return reset_execution_page($req, $session, $arg);
    }else{
	# トップページ
	return top_page($req, $session, $arg);
    }
    
    # /password
    # - ユーザID，現在のパスワード，新しいパスワードの入力を求める
    # /password_change
    # - 現在のパスワードを確認
    # - パスワードを変更
};

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
# 東京学芸大学 学生向けの各種情報のトップページ
sub top_page {
    my ($req, $session, $arg) = @_;

    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('gakugei_top.html', $arg));
    $res->finalize();
}

sub account_page {
    my ($req, $session, $arg) = @_;

    # ページ出力などの際に用いる最小限の引数みたいなものか
    $arg->{title} = 'ユーザ登録';

    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('gakugei_account.html', $arg));
    $res->finalize();
}

# ユーザ情報の確認
sub account_confirm_page {
    my ($req, $session, $arg) = @_;

    # ページ出力などの際に用いる最小限の引数みたいなものか
    $arg->{title} = 'ユーザ登録確認';

    # フォームに入力されたユーザ情報を取得
    my $user_data = read_user_data($req, $session, $arg);

    if(defined($user_data)){
	
	while(my ($key, $value) = each(%{$user_data})){
	    $arg->{$key} = $value;
	}
 	$user_data->{fullname}    = sprintf("%s %s",
					    $user_data->{family_name},
					    $user_data->{first_name});
	$user_data->{fullname_ja} = sprintf("%s %s",
					    $user_data->{family_name_ja},
					    $user_data->{first_name_ja});

	# ファイルに一時保存
	# - メールアドレスの確認後にデータベースに登録する
	file_out_user_data($user_data, 'register');

	# ログ
	print_log(
	    sprintf("INFO: account_confirm %s (%s).",
		    $user_data->{userid},
		    $user_data->{mail_address}),
	    $session
	    );

	# メール送信
	if(send_mail('gakugei_account_confirm', $user_data)){
	    print_log( 
		sprintf("INFO: Send mail to %s.",
			$user_data->{mail_address}),
		$session
	    );
	}else{
	    $arg->{error} = 'メール送信に失敗しました．';
	}
    }

    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('gakugei_account_confirm.html', $arg));
    $res->finalize();
}

# アカウント登録
# - メールで送ったチケットを入力してもらう
sub account_register_page {
    my ($req, $session, $arg) = @_;

    # ページ出力などの際に用いる最小限の引数みたいなものか
    $arg->{title} = 'ユーザ登録';

    my $parameters = $req->parameters();
    my $ticket = $parameters->get('ticket');
    my $user_data = read_user_data_from_ticket($ticket);
    if(defined($user_data)){

	while(my ($key, $value) = each(%{$user_data})){
	    $arg->{$key} = $value;
	}

	# 本当はトランザクション処理をしないといけないか
	my $db_data = $DB->single_by_sql
	    (
	     q{SELECT id,userid,realm FROM ptuser WHERE mail_address = ?}, 
	     [
	      $user_data->{mail_address}
	     ]
	    );
	if(defined($db_data)){
	    print_log(sprintf("ERROR: The mail address (%s) has been already registered.", $user_data->{mail_address}),
		$session);
	    $arg->{error} = sprintf("メールアドレス \"%s\" は登録済みです．", $user_data->{mail_address});
	    return;
	}
	
	eval{
	    # 新規ユーザ登録
	    $db_data = $DB->insert
		('ptuser', 
		 {
		     userid       => $user_data->{userid},
		     password     => md5_hex($user_data->{password}),
		     fullname     => $user_data->{fullname},
		     fullname_ja  => $user_data->{fullname_ja},
		     mail_address => $user_data->{mail_address},
		     realm        => $CONFIG{REALM_GAKUGEI},
		     register_date => 'now'
		 }
		);
	};
	if($@){
	    # データベースへの登録エラー
	    $arg->{error} = "登録に失敗しました．しばらく待ってから再度登録を試みてください．";
	    print_log(sprintf("ERROR: %s", $@));
	}else{

	    # ログ
	    print_log(
		sprintf("INFO: account_register %s.",
			$user_data->{userid}),
		$session
		);
	    reset_ticket($ticket);
	    
	    # 登録完了を知らせるメールを送信
	    if(send_mail('gakugei_account_register', $user_data)){
		print_log( 
		    sprintf("INFO: Send mail to %s.",
			    $user_data->{mail_address}),
		    $session
		    );
	    }
	}
    }else{
	# ファイルに保存した仮登録のデータが見つからない
	$arg->{error} = "ユーザ情報が見つかりません．最初から登録を試みてください．";
	print_log(sprintf("ERROR: Cannot find a user data for the ticket(%s).", $ticket), $session);
    }

    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('gakugei_account_register.html', $arg));
    $res->finalize();
}

# パスワードリセット
sub reset_page {
    my ($req, $session, $arg) = @_;

    # ページ出力などの際に用いる最小限の引数みたいなものか
    $arg->{title} = 'パスワードリセット';

    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('gakugei_reset.html', $arg));
    $res->finalize();
}

# パスワードリセットの確認
sub reset_confirm_page {
    my ($req, $session, $arg) = @_;

    # ページ出力などの際に用いる最小限の引数みたいなものか
    $arg->{title} = 'パスワードリセットの確認';
    
    # 入力されたメールアドレス
    # - ごく簡単なチェックしか行わない
    my $parameters   = $req->parameters();
    my $mail_address = $parameters->get('mail_address');
    $mail_address =~ s/\s+//g;

    if($mail_address !~ /[^\@]+\@[^\@]+/){
	# メールアドレスに問題あり
	$arg->{error} = '不正なメールアドレスです．';
	print_log(sprintf("ERROR: Bad mail address (%s).", $mail_address));
    }else{
	# メールアドレスは問題なし
	$arg->{mail_address} = $mail_address;

	my $db_data = $DB->single_by_sql
	    (
	     q{SELECT id,userid,realm,mail_address,fullname,fullname_ja FROM ptuser WHERE mail_address = ?}, 
	     [
	      $mail_address,
	     ]
	);
	if(defined($db_data)){
	    my $user_data = {
		userid       => $db_data->userid(),
		mail_address => $mail_address,
		fullname     => $db_data->fullname(),
		fullname_ja  => $db_data->fullname_ja()
	    };

	    file_out_user_data($user_data, 'reset');

	    # ログ
	    print_log(
		sprintf("INFO: reset_confirm %s.",
			$user_data->{userid}),
		$session
		);

	    # メール送信
	    if(send_mail('gakugei_reset_confirm', $user_data)){
		print_log( 
		    sprintf("INFO: Send mail to %s.",
			    $user_data->{mail_address}),
		    $session
		    );
	    }else{
		$arg->{error} = 'メール送信に失敗しました．';
	    }
	}else{
	    print_log(sprintf("ERROR: Unknown mail address (%s).", $mail_address));
	    $arg->{error} = sprintf("メールアドレス \"%s\" は登録されていません．", $mail_address);
	}
    }

    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('gakugei_reset_confirm.html', $arg));
    $res->finalize();
}

# パスワードのリセット
sub reset_execution_page {
    my ($req, $session, $arg) = @_;

    my $parameters = $req->parameters();
    my $ticket = $parameters->get('ticket');
    my $user_data = read_user_data_from_ticket($ticket);
    
    if(defined($user_data)){

	while(my ($key, $value) = each(%{$user_data})){
	    $arg->{$key} = $value;
	}

	my $db_data = $DB->single_by_sql
	    (
	     q{SELECT id,userid,realm,password FROM ptuser WHERE userid = ? AND realm = ?}, 
	     [
	      $user_data->{userid},
	      $CONFIG{REALM_GAKUGEI},
	     ]
	    );
	if(defined($db_data)){
	    eval{
		# パスワードリセット
		$db_data->update({
		    password => md5_hex($user_data->{password})
				 });
	    };
	    if($@){
		# データベースへの登録エラー
		$arg->{error} = "パスワードリセットに失敗しました．";
		print_log(sprintf("ERROR: %s", $@));
	    }else{

		# ログ
		print_log(
		    sprintf("INFO: reset_execution %s.",
			    $user_data->{userid}),
		    $session
		    );
		reset_ticket($ticket);
		
		# リセット完了を知らせるメールを送信
		if(send_mail('gakugei_reset_execution', $user_data)){
		    print_log( 
			sprintf("INFO: Send mail to %s.",
				$user_data->{mail_address}),
			$session
			);
		}
	    }
	    
	}else{
	    $arg->{error} = "ユーザとして登録されていません．";
	}
    }else{
	# ファイルに保存した仮登録のデータが見つからない
	$arg->{error} = "ユーザ情報が見つかりません．最初からリセットを試みてください．";
	print_log(sprintf("ERROR: Cannot find a user data for the ticket(%s).", $ticket));
    }

    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('gakugei_reset_execution.html', $arg));
    $res->finalize();
}

# ページ出力
sub render{
    my ($name, $arg) = @_;

    # 管理者 [% admin %] は tsekiya@u-gakugei
    $arg->{admin} = $CONFIG{PAGE_ADMIN_GAKUGEI};

    my $tt = Template->new($TEMPLATE_CONFIG);
    my $out;
    $tt->process( $name, $arg, \$out );
    return $out;
}

########################################################################
# ユーザ登録
########################################################################
sub read_user_data {
    my ($req, $session, $arg) = @_;

    my $parameters = $req->parameters();

    my $user_data = {};
    
    my $userid = $parameters->get('userid');
    $userid =~ s/\s+//g;
    if ( $userid !~ /^([a-z]\d+)$/i ) {
	$arg->{error} =
            'ユーザ名は"アルファベット1文字+数字6文字"としてください．';
	print_log("ERROR: Invalid user_name $userid.", $session);
	return;
    }
    $user_data->{userid} = lc($1);

    # メールアドレス
    my $mail_address = $parameters->get('mail_address');
    if ( $mail_address !~ /(\S+\@[\w\.\-]+)/ ) {
	$arg->{error} =
            'メールアドレスが間違っていないか確認してください．';
        print_log("ERROR: Invalid mail_address $mail_address.", $session);
    }
    $user_data->{mail_address} = $1;

    # 名(ローマ字)
    my $first_name = $parameters->get('first_name');
    if ( $first_name !~ /([a-z]+)/i ) {
	$arg->{error} =
            '名(ローマ字)にアルファベット以外の文字が含まれていないか確認してください．';
	print_log("ERROR: Invalid first_name $first_name.", $session);
    }
    $user_data->{first_name} = ucfirst( lc($1) );

    # 姓(ローマ字)
    my $family_name = $parameters->get('family_name');
    if ( $family_name !~ /([a-z]+)/i ) {
	$arg->{error} =
            '姓(ローマ字)にアルファベット以外の文字が含まれていないか確認してください．';
	print_log("ERROR: Invalid family_name $family_name.", $session);
    }
    $user_data->{family_name} = uc($1);

    # 名(日本語)
    my $first_name_ja = $parameters->get('first_name_ja');
    if ( $first_name_ja !~ /(\S+)/ ) {
	$arg->{error} = '名(日本語)を確認してください．';
        print_log("ERROR: Invalid first_name_ja $first_name_ja.", $session);
    }
    $user_data->{first_name_ja} = $1;

    # 姓(日本語)
    my $family_name_ja = $parameters->get('family_name_ja');
    if ( $family_name_ja !~ /(\S+)/ ) {
	$arg->{error} = '姓(日本語)を確認してください．';
        print_log("ERROR: Invalid family_name_ja $family_name_ja.", $session);
    }
    $user_data->{family_name_ja} = $1;

    return $user_data;
}

sub read_user_data_from_ticket {
    my ($ticket) = @_;

    # 不適切な文字を修正
    $ticket =~ s/[^\w\-_]//g;
    $ticket =~ s/\.//g;

    # ファイルを読込む
    my $file = $CONFIG{GAKUGEI_USER_DATA_DIR} . "/$ticket";
    if ( !-f $file ) {
        print_log("ERROR: Cannot find $file.");
	return;
    }
    my $fh = FileHandle->new( $file, O_RDONLY );
    if ( !defined($file) ) {
        print_log("ERROR: Cannot open $file.");
        return;
    }
    my $line = $fh->getline();
    $fh->close();

    # 必要な情報を抽出する
    if ( $line !~ /^([\w\-\.]+):([\@\w\-\.]+):([\w\s]+):(.+\S)/ ) {
        print_log("ERROR: Invalid Data ($_).");
        return;
    }

    my $user_data = {};
    $user_data->{userid}       = lc($1);
    $user_data->{mail_address} = $2;
    $user_data->{fullname}     = $3;
    $user_data->{fullname_ja}  = $4;
    $user_data->{password}     = generate_password();

    return $user_data;
}

# チケット用のファイルを削除
sub reset_ticket {
    my ($ticket) = @_;

    # 不適切な文字を修正
    $ticket =~ s/[^\w\-_]//g;
    $ticket =~ s/\.//g;

    # ファイルを読込む
    my $file = $CONFIG{GAKUGEI_USER_DATA_DIR} . "/$ticket";
    if ( !-f $file ) {
        print_log("ERROR: Cannot find $file.");
	return;
    }
    unlink($file);
    print_log("INFO: Delete $file.");

    return;
}

##########################################
# ファイルへの出力
##########################################
sub file_out_user_data {
    my ($user_data, $mode) = @_;

    my $userid = $user_data->{userid};

    # 出力先の準備
    my ($sec, $min, $hour, $mday, $mon, $year, undef, undef, undef ) =
        localtime;
    my $file_basename = POSIX::strftime( $mode . "_%Y-%m-%d-$userid",
        $sec, $min, $hour, $mday, $mon, $year )
        . '-' 
        . generate_key();
    # 長い文字列だが，直接手入力することは想定しないのでよしとする
    $user_data->{ticket} = $file_basename; 
    
    my $file = $CONFIG{GAKUGEI_USER_DATA_DIR} . "/$file_basename";

    # 取り敢えず file lock などは考えない
    my $fh = FileHandle->new( $file, O_WRONLY | O_CREAT | O_APPEND, 0664 );
    $fh->printf("%s:%s:%s:%s\n",
        $userid,
        $user_data->{mail_address},
        $user_data->{fullname},
        $user_data->{fullname_ja});
    $fh->close();
}

############################
# メールの送信
############################
# メールを送信するのみ
sub send_mail($$) {
    my ( $mail_id, $mail_data ) = @_;

    # 付加情報
    $mail_data->{sender}     = $CONFIG{PAGE_ADMIN_GAKUGEI};
    $mail_data->{hostname}   = $CONFIG{HOSTNAME};
    $mail_data->{common_url} = $CONFIG{GAKUGEI_COMMON_URL};

    # 一時ファイル
    my $tmp_file = $CONFIG{TMP_DIR} . '/mail_jis_' . $$;
    unlink($tmp_file) if(!-f $tmp_file);

    # 文字コード変換
    my $output =
        FileHandle->new( "| /usr/bin/iconv -f utf8 -t ISO-2022-JP > $tmp_file");
    return 0 unless ($output);

    # Template を使ったファイルの作成
    my $template = Template->new($TEMPLATE_CONFIG);

    $template->process( $mail_id . ".mail",  $mail_data, $output)
        or die $template->error();
    $output->close();

    # メールの送信
    my $mailer = Net::SMTP::SSL->new(
	$CONFIG{GAKUGEI_MAIL_SMTP_SERVER},
	Port     => 465);
    if(!defined($mailer)){
	print_log("ERROR: Cannot connect to mail server over SSL.");
	return 0;
    }
    if(!$mailer->auth($CONFIG{GAKUGEI_MAIL_USERID}, $CONFIG{GAKUGEI_MAIL_PASSWORD})){
	print_log("ERROR: Authentication of mail server failed.");
	return 0;
    }	

    $mailer->mail($CONFIG{PAGE_ADMIN_GAKUGEI});
    $mailer->to($mail_data->{mail_address});
    $mailer->data();

    # 作成したファイルの読み込み
    my $fh = FileHandle->new($tmp_file, O_RDONLY);
    return 0 if(!defined($fh));
    while(my $line = $fh->getline()){
	$mailer->datasend($line);
    }
    $fh->close();

    $mailer->dataend();
    $mailer->quit();
 
    # 一時ファイルの削除
    unlink($tmp_file) if(!-f $tmp_file);

    return 1;
}

##########################################
# ログの出力
##########################################
sub print_log {
    my ($message, $session) = @_;

    my $debug_info = '';
    if(defined($session)){
	# 付加情報
	my $session_id = '';
	$session_id = $session->id() if(defined($session->id()));
	my $client_ip = '';
	$client_ip = $session->get('client_ip') if(defined($session->get('client_ip')));
	$debug_info = sprintf("[%s] [%s]",
		    $session_id,
		    $client_ip);
    }

    # Log 関係
    my ( $sec, $min, $hour, $mday, $mon, $year, undef, undef, undef ) =
        localtime;
    my $log_date =
        POSIX::strftime( "%Y/%m/%d %H:%M:%S", $sec, $min, $hour, $mday, $mon, $year );
    my $target_log_dir = $CONFIG{LOG_DIR} 
        . POSIX::strftime( "/%Y/%m", $sec, $min, $hour, $mday, $mon, $year );
    my_mkdir($target_log_dir);
    my $log_file = $target_log_dir
        . POSIX::strftime( "/" . LOG_FILE_BASENAME . ".%Y-%m-%d",
        $sec, $min, $hour, $mday, $mon, $year );

    # 取り敢えず file lock などは考えない
    my $fh =
        FileHandle->new( $log_file, O_WRONLY | O_CREAT | O_APPEND, 0664 );
    $fh->printf("%s [%s]: %s (%s)\n", 
		$log_date,
		$$,
		$message,
		$debug_info);
    $fh->close();
}

##########################################
# ログの出力
##########################################
sub my_mkdir($) {
    my $target_dir = shift;
    my $parent_dir = $target_dir;

    $parent_dir =~ s/\/([^\/]+)(\/|)$//;

    if ( !-d $parent_dir ) {
        my_mkdir($parent_dir);
    }
    mkdir( $target_dir, 0775 );

    return $target_dir;
}

sub generate_key() {

    my $password = '';
    for ( my $i = 0; $i < KEY_LENGTH; $i++ ) {
        $password .= chr(
            int( rand(NUMBER_OF_ALPHABET) ) + ASCII_CODE_OF_LOWERCASE_A );
    }

    return $password;
}

sub generate_password(){
    my ($self) = @_;

    my $password = '';
    for(my $i = 0; $i < LENGTH_OF_PASSWORD; $i++){
        $password .= 
            chr(int(rand(NUMBER_OF_ALPHABET)) + ASCII_CODE_OF_LOWERCASE_A);
    }

    return $password;
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
    enable 'AccessLog', logger => sub {$LOGGER->log(level => 'debug', message => @_)};
    #
    enable "Plack::Middleware::Static",
    path => qr/static/,
    root => '.';
    enable 'Session',
    store => Plack::Session::Store::File->new(
	dir => '/usr/local/plack/tracing/sessions'
        );
    enable "Plack::Middleware::REPL";
    enable "Plack::Middleware::Lint";
    $APP;
};
