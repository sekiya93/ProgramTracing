
package BLTI;

use strict;
use warnings;
use utf8;

use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request::Common;
use OAuth::Lite::ServerUtil;
use OAuth::Lite::Consumer;
use MIME::Base64;
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);
use Data::UUID;

use constant{
    CONFIG_DIR        => 'conf',
};
my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
my %CONFIG;
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

use Template;
my $TEMPLATE_CONFIG = {INCLUDE_PATH => $CONFIG{TEMPLATE_DIR}};

use URI::Escape;

sub is_blti_req {
	my ($req, $session) = @_;
	my $value = $req->parameters()->get('lti_version');
	if(!defined($value)){
		print STDERR "!LTI\n";
		return 0;
	}
	return 1; 
}

sub blti_req {
	my ($req, $session) = @_;

	my $path_info = $req->path_info();
	
	# check oauth parameters
	my $util = OAuth::Lite::ServerUtil->new(strict => 0);
    $util->support_signature_method('HMAC-SHA1');

    unless ($util->validate_params($req->parameters())) {
    	print STDERR "LTI: oauth failed(1)\n";
        return 0;
    }

    unless ($util->verify_signature(
        method          => $req->method,
        params          => $req->parameters(),
        url             => $req->uri,
        consumer_secret => $CONFIG{OAUTH_CONSUMER_SECRET},
    )){
    	print STDERR "LTI: oauth failed(2)\n";
    	return 0;
    }
    
	my $realm = $req->parameters()->get('oauth_consumer_key');
	my $username = $req->parameters()->get('lis_person_contact_email_primary');
	my $userid = $req->parameters()->get('user_id');
	my $roles = $req->parameters()->get('roles');
	
	$session->set('verified', 1);
	$session->set('userid',   $userid);
	$session->set('username', $username);
	$session->set('realm',    $realm);
	$session->set('mode',     'student');
	$session->set('roles', $roles);
	$session->set('lis_outcome_service_url', $req->parameters()->get('lis_outcome_service_url'));
	$session->set('lis_result_sourcedid', $req->parameters()->get('lis_result_sourcedid'));
	$session->set('oauth_consumer_key', $req->parameters()->get('oauth_consumer_key'));
	
	print STDERR "LTI: $path_info, $realm, $username, $userid\n";
	return 1;
}

sub my_url_prefix {
	return sprintf("%s://%s:%s/", $CONFIG{HTTPPROT}, $CONFIG{HOSTNAME}, $CONFIG{HTTPPORT});
}

sub tool_config {
	my ($req, $arg) = @_;
	
	$arg->{urlPrefix} = my_url_prefix();
	$arg->{hostname} = $CONFIG{HOSTNAME};
	print STDERR Data::Dumper->Dump([$arg]);
	
	# ページ出力のための準備
    my $res = $req->new_response(200);
    $res->content_type('text/xml');
    $res->body(render('tool_config.xml', $arg));
    $res->finalize();
}

# テスト一覧(LTI:resource_selection)
sub list_exam_rs {
    my ($req, $arg) = @_;

	my $urlPrefix = $req->param('launch_presentation_return_url');
	
    # テスト一覧の読み込み
    my @exams = Exam::File->exam_list();
    $arg->{exam_list} = '';

    foreach my $exam (sort{$a->id() cmp $b->id()} @exams){
		# 非公開の試験はスキップ
		#next unless($arg->{realm} eq $CONFIG{REALM_ECCS} && $exam->is_open_to_eccs() ||
		#    $arg->{realm} eq $CONFIG{REALM_GAKUGEI} && $exam->is_open_to_gakugei());
		# next if(! $exam->is_open());
		$arg->{exam_list} .= 
	    sprintf("<li><a href=\"%s?embed_type=basic_lti&title=%s&text=%s&url=%stake_exam%%3Fexam_id%%3D%s\">%s (id:%s, %s 更新)</a></li>\n",
	    	$urlPrefix,
	    	uri_escape_utf8($exam->name()),
	    	uri_escape_utf8($exam->name()),
	    	uri_escape_utf8(my_url_prefix()),
		    $exam->id(),
		    $exam->name(),
		    $exam->id(),
		    $exam->modified()
	    );
    }

    # ページ出力のための準備
    my $res = $req->new_response(200);
    $res->content_type('text/html');
    $res->body(render('resource_selection.html', $arg));
    $res->finalize();
}

sub send_result {
	my ($req, $session, $grade) = @_;
	my $url = $session->get('lis_outcome_service_url');
	
	if(defined($url)){
	
		my $arg = {
			messageId => Data::UUID->new->create_str,
			sourceId => $session->get('lis_result_sourcedid'),
			grade => $grade,
			resultUrl => sprintf('%sadmin_answers?exam_id=%s', my_url_prefix(), $req->param('exam_id'))
		};
		
		my $body = render('resultData.xml', $arg);
		print STDERR "LTI(req): $url, $body\n";
			
		my $hash = sha1_base64($body);
		print STDERR "LTI(oauth): $url, $hash\n";
		my $params = { 'oauth_body_hash' => $hash };
		my $consumer = OAuth::Lite::Consumer->new(
			consumer_key    => $session->get('oauth_consumer_key'),
			consumer_secret => $CONFIG{OAUTH_CONSUMER_SECRET},
		);
	    my $res = $consumer->request(
	        method  => 'POST',
	        url     => $url,
	        headers => [ 'Content-Type' => 'application/xml' ],
	        content => $body,
	        params  => { 'oauth_body_hash' => $hash },
	    );
		if ($res->is_success) {
			print STDERR "LTI(send_result): SUCCESS\n";
	    }else{
	    	print STDERR "LTI(send_result): FAILURE\n";
	    }

	}else{
		print STDERR "LTI: no url found\n";
	}
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

1;