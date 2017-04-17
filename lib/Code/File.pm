############################################################
#
# Code::File
#
# Time-stamp: <2013-06-17 23:41:58 sekiya>
#
############################################################
# - 答案情報の実体はファイルで管理するが，オブジェクトとして
#   取扱い可能とする．
# - method 名の取得について，C++ を対象とするように改良
#   (Thu May 23 07:33:56 2013)
package Code::File;

use Moose;

use constant{
    CONFIG_DIR        => 'conf',
    #
    DEFAULT_SUFFIX    => 'rb',
    RUBY_SUFFIX       => 'rb',
    CPP_SUFFIX        => 'cpp',
};

use Config::Simple;
use POSIX;
use Data::Dumper;

my %CONFIG;
my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

# key => {name => ..., code => ..., mtime => ...}
our %CODE_HASH = ();

#######################################
# 属性定義
#######################################
has 'name' => (
    is => 'rw'
);

has 'code' => (
    is => 'rw'
);

has 'mtime' => (
    is => 'rw'
);

has 'method_name' => (
    is => 'rw'
);

has 'p_variable' => (
    is => 'rw'
);

has 'suffix' => (
    is => 'rw'
);

#######################################
# ファイル読み書き
#######################################
sub _read_all_codes{

    #
    # RUBY_CODE_DIR よりファイルを読込み
    #
    foreach my $file (glob($CONFIG{RUBY_CODE_DIR} . '/*.{rb,txt,pl,c,cpp}')){
	# name の抽出
	next if($file !~ /\/([^\/]+)$/);
	my $name = $1;

	# suffix の抽出 (Thu May 23 07:36:19 2013)
	my $suffix;
	if($file =~ /\.(\w+)$/){
	    $suffix = $1;
	}else{
	    $suffix = DEFAULT_SUFFIX;
	}

	# mtime の比較
	my @col = stat($file);
	my $mtime = $col[9];
	next if(exists($CODE_HASH{$name}) && $CODE_HASH{$name}->mtime() >= $mtime);
	    
	my $fh = FileHandle->new($file, O_RDONLY);
	die "Cannot open $file." if(!defined($fh));
	my $code_string = '';
	my $method_name = '';
	my $p_variable  = '';
	while(my $line = $fh->getline()){
	    $code_string .= $line;

	    # メソッド名
	    if($suffix eq DEFAULT_SUFFIX && $line =~ /^\s*def\s+(\w+)/i){
		$method_name = $1;
	    }elsif($suffix eq CPP_SUFFIX && $line =~ /^\s*(\w+)\s+(\w+)\(.+\{/i){
		# これで十分かどうかは要確認
		$method_name = $2;
	    }
		
	    # 戻り値...というよりはメソッドの最後に出力する形式
	    # - "p ans" のような行が1行だけ存在する事が前提
	    $p_variable = $1 if($line =~ /^\s*p\s*\(*(\w+)\)*\s*$/i);
	}
	$fh->close();


	my $obj = Code::File->new(
	    name        => $name,
	    code        => $code_string,
	    mtime       => $mtime,
	    method_name => $method_name,
	    p_variable  => $p_variable,
	    suffix      => $suffix,
	    );

	$CODE_HASH{$name} = $obj;
    }

    #
    # 存在しないコードを削除
    #
    while(my ($name, $obj) = each(%CODE_HASH)){
	my $file = sprintf("%s/%s", $CONFIG{RUBY_CODE_DIR}, $name);
	delete($CODE_HASH{$name}) if(! -f $file);
    }

    # print STDERR "Code::File " . Data::Dumper->Dump([\%CODE_HASH]);
}

#######################################
# オブジェクトの取得
#######################################
# - クラス変数の代りに %CODE_HASH を用いる
# - ファイルが更新されるまでは，id が同じオブジェクトは
#   同一のオブジェクトになる
# -- 一方を修正すると他方にも修正が反映される

# 一覧取得
sub code_list{

    _read_all_codes();

    return \%CODE_HASH;
}

# 一個
sub get_by_name{
    my ($self, $name) = @_;

    _read_all_codes();

    $name =~ s/[\/\[\]\{\}]//g;

    if(exists($CODE_HASH{$name})){
	return $CODE_HASH{$name};
    }else{
	return undef;
    }
}

#######################################
# コード種別
#######################################
sub is_cpp{
    my ($self) = @_;

    return $self->{suffix} eq CPP_SUFFIX;
}

sub is_ruby{
    my ($self) = @_;

    return $self->{suffix} eq RUBY_SUFFIX;
}

#######################################
# ユーティリティ
#######################################
# 値を文字列に変換
# - 配列の処理を整理するために用いる
sub _value_to_string{
    my ($value) = @_;

    if(ref($value) eq 'ARRAY'){
	return '[' . join(', ', @{$value}) . ']';
    }else{
	return $value;
    }
}

# 文字列を値変換
# - 配列の処理を整理するために用いる
sub _string_to_value{
    my ($string) = @_;

    $string =~ s/\s//g;
    if($string =~ /^\[(.+)\]$/){
	my @col = ();
 	map{push(@col, eval($_))} split(/,/, $string);
	return \@col;
    }else{
	return $string;
    }
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;
