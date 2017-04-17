############################################################
#
# PTAuth.pm
#
# Time-stamp: <2014-05-11 10:29:03 sekiya>
#
############################################################
# - 認証に特化
package PTAuth;

use constant{
    CONFIG_DIR        => 'conf',
};

# ローカルのモジュールを利用するため，ライブラリのパスを
# 明示的に設定
use lib '/usr/local/plack/tracing/lib';

use Config::Simple;
use FileHandle;
use Digest::MD5 qw(md5_hex);

my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
my %CONFIG;
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

use Mail::IMAPClient;
use PTDB;
our $DB = PTDB->new(
    {
	connect_info => ['DBI:Pg:dbname=' . $CONFIG{DBNAME} . ';host=' . $CONFIG{DBHOST} . ';', $CONFIG{DBUSER}]
    });

# ローカルのパスワード情報
my %LOCAL_USER_DATA = ();
my $local_user_file = sprintf("%s/local_user.dat", CONFIG_DIR);
my $fh = FileHandle->new($local_user_file, O_RDONLY);
if(-f $local_user_file && defined($fh)){
    while(my $line = $fh->getline()){
	chomp($line);
	next if($line =~ /^\#/);
	my ($userid, $fullname, $digest) = split(/:/, $line);
	$LOCAL_USER_DATA{$userid} = 
	{
	    userid   => $userid,
	    fullname => $fullname,
	    digest   => $digest
	};
    }
    $fh->close();
}

#######################################
# 全体
#######################################
# 認証
# - 個別の認証処理をまとめたもの
sub auth{
    my ($userid, $password, $arg) = @_;

    # userid は英小文字とハイフン，数字のみ許可
    $userid =~ s/[^a-z\d\-]//g;

#    if(auth_gakugei($userid, $password)){
#	# 東京学芸大学用
#	$arg->{realm} = $CONFIG{REALM_GAKUGEI};
#	return 1;
#    }elsif(auth_local($userid, $password)){
	if(auth_local($userid, $password)){
	# ローカル認証
	$arg->{realm} = $CONFIG{REALM_LOCAL};
	return 1;
    }elsif(auth_eccs($userid, $password)){
	# ECCS
	$arg->{realm} = $CONFIG{REALM_ECCS};
	return 1;
    }else{
	return 0;
    }
}

#######################################
# 個別
#######################################
sub auth_local{
    my ($userid, $password) = @_;
print STDERR  md5_hex($password);
print STDERR  "\n";
print STDERR  $LOCAL_USER_DATA{$userid}->{digest};
print STDERR  "\n";
    return (exists($LOCAL_USER_DATA{$userid}) && 
	    $LOCAL_USER_DATA{$userid}->{digest} eq md5_hex($password));
}

# ECCS
sub auth_eccs{
    my ($userid, $password) = @_;

    my $imap = Mail::IMAPClient->new(
        Server   => $CONFIG{ECCS_MAIL_SERVER},
        User     => $userid,
        Password => $password,
	Ssl      => 1,
        );
    # or die "IMAP Server Error ($@, $userid, $password)";

    # その他のエラー
    unless($imap){
	print STDERR  "IMAP Server Error ($@, $userid, $password)";
	return 0;
    }

    $imap->logout();

    return 1;
}

# 東京学芸大学用
sub auth_gakugei{
    my ($userid, $password) = @_;

    my $user = $DB->single_by_sql
	(
	 q{SELECT id,userid,realm FROM ptuser WHERE userid = ? AND realm = ? AND password = ?}, 
	 [$userid,
	  $CONFIG{REALM_GAKUGEI},
	  md5_hex($password)
	 ]
	);
    return (defined($user));
}

#######################################
# その他
#######################################
# 姓名情報の取得
sub get_fullname{
    my ($arg) = @_;

    if($arg->{realm} eq $CONFIG{REALM_GAKUGEI}){
	# 東京学芸大学用の場合
	my $user = $DB->single_by_sql
	    (
	     q{SELECT id,userid,fullname_ja,realm FROM ptuser WHERE userid = ? AND realm = ?}, 
	     [$arg->{userid},
	      $CONFIG{REALM_GAKUGEI},
	     ]
	    );
	if(defined($user)){
	    $arg->{fullname} = $user->fullname_ja();
	}
    }elsif(defined($arg->{username})){
    	$arg->{fullname} = $arg->{username};
    }elsif($arg->{realm} eq $CONFIG{REALM_LOCAL}){
		# ローカル認証の場合 
		$arg->{fullname} = $LOCAL_USER_DATA{$arg->{userid}}->{fullname};
    }else{
		# その他 
		$arg->{fullname} = $arg->{userid};
    }

    return $arg->{fullname};
}

1;
