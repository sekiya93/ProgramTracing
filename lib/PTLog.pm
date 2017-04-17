########################################
#
#  PTLog.pm
#  
#  Created: Fri Apr  5 10:17:30 2013
#  Time-stamp: <2013-04-05 11:34:12 sekiya>
#
########################################
package PTLog;

#########################################################
# 初期設定
#########################################################
use constant{
    CONFIG_DIR        => 'conf',
};

use constant{
    # 設定ファイル
    CONFIG_FILE => CONFIG_DIR . "/log.conf",
};

our(%CONFIG, $LOG);

use POSIX;
setlocale(LC_ALL, 'C');
use Config::Simple;
use Log::Log4perl;

# 設定ファイルを読み込む
Config::Simple->import_from(CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

sub init{
    my ($class) = @_;

    # インスタンス
    my $self = {};
    bless $self, $class;

    # ログの設定
    Log::Log4perl->init($CONFIG{LogConfFile})
	or die "cannot read " . $CONFIG{LogConfFile};
    $LOG = Log::Log4perl->get_logger('');

    return $self
}

sub get_log_filename(){
    my ($self) = @_;

    my ($SEC, $MIN, $HOUR, $MDAY, $MON, $YEAR, undef, undef, undef) =
	localtime;
    my $log_year_dir = $CONFIG{LogDirectory} . 
	POSIX::strftime("/%Y", $SEC, $MIN, $HOUR, $MDAY, $MON, $YEAR);
    mkdir($log_year_dir, 0755) if(! -d $log_year_dir);
    my $log_month_dir = $log_year_dir . 
	POSIX::strftime("/%m", $SEC, $MIN, $HOUR, $MDAY, $MON, $YEAR);
    mkdir($log_month_dir, 0755) if(! -d $log_month_dir);
    
    return $log_month_dir .
	POSIX::strftime("/" . $CONFIG{LogBasename} . ".%Y-%m-%d",
			$SEC, $MIN, $HOUR, $MDAY, $MON, $YEAR);
}

################################################
# ログ出力
################################################
# $session_data: id, userid, session_key
sub put_log{
    my ($self, $method, $message, $session) = @_;

    if(defined($session)){
	# 付加情報
	my $session_id = '';
	$session_id = $session->id() if(defined($session->id()));
	my $userid = '';
	$userid = $session->get('userid') if(defined($session->get('userid')));
	my $realm = '';
	$realm = $session->get('realm') if(defined($session->get('realm')));
	my $client_ip = '';
	$client_ip = $session->get('client_ip') if(defined($session->get('client_ip')));

	$message = 
	    sprintf("[%s] [%s\@%s %s] %s",
		    $session_id,
		    $userid,
		    $realm,
		    $client_ip,
		    $message);
    }
		
    $LOG->$method($message);
}

sub debug{
    my ($self, $message, $session) = @_;

    $self->put_log('debug', $message, $session);
}

sub info{
    my ($self, $message, $session) = @_;

    $self->put_log('info', $message, $session);
}

sub warn{
    my ($self, $message, $session) = @_;

    $self->put_log('warn', $message, $session);
}

sub error{
    my ($self, $message, $session) = @_;

    $self->put_log('error', $message, $session);
}

1;
