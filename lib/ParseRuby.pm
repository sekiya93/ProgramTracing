################################################
# 
# Ruby Program の処理
#
# Time-stamp: <2013-08-08 15:37:37 sekiya>
#
################################################
# 1. ruby parser を使って，ruby プログラムをS式に
# 2. S式から元の ruby プログラムに
# 3. S式と本パッケージ内部の独自形式に
# 4. ruby のプログラムを適宜処理

package ParseRuby;

#########################################################
# 初期設定
#########################################################
# 基本はハッシュ
# ->{type} = "predicate", "symbol", "literal"
# ->{predicate} = ":defn", ":args", ...
# ->[]

use constant{
    CONFIG_DIR        => 'conf',
    #
    TMP_DIR => '/var/tmp/',
    RUBY    => 'ruby',
    #
    TYPE_PREDICATE => 'predicate',
    TYPE_LITERAL   => 'literal',
    TYPE_SYMBOL    => 'symbol',
    #
    INDENT => '  ',
};

use FileHandle;
use Carp;
use English;
use Data::Dumper;

our %REVERSE_PARSE_METHOD_HASH = (
    ':and'      => 'reverse_parse_and',
    ':arglist'  => 'reverse_parse_arglist',
    ':array'    => 'reverse_parse_array',
    ':attrasgn' => 'reverse_parse_array_assignment',
    ':block'    => 'reverse_parse_block',
    ':call'     => 'reverse_parse_call',
    ':dot2'     => 'reverse_parse_dot2',
    ':for'      => 'reverse_parse_for',
    ':if'       => 'reverse_parse_if',
    ':lasgn'    => 'reverse_parse_assignment',
    ':lit'      => 'reverse_parse_literal',
    ':lvar'     => 'reverse_parse_lvar',
    ':scope'    => 'reverse_parse_scope',
    ':while'    => 'reverse_parse_while',
    );

# DEBUG:
# 9以上: 内部表現の dump
# 4以上: Ruby     -> S式
# 3以上: S式      -> 内部表現 処理
# 2以上: 内部表現 -> S式
# 1以上: 内部表現 -> Ruby 
use constant{
    DEBUG_INTERNAL_DATA                => 9,
    DEBUG_GENERATE_S_EXPRESSION        => 4,
    DEBUG_PARSE_S_EXPRESSION           => 3,
    DEBUG_REVERSE_PARSE_S_EXPRESSION   => 2,
    DEBUG_REVERSE_PARSE_RUBY           => 1,
};
my $DEBUG = DEBUG_REVERSE_PARSE_RUBY;

use Config::Simple;
my %CONFIG;
my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

#########################################################
# 初期化
#########################################################
sub new{
    my $type = shift;
    my $self = {};

    bless $self, $type;

    return $self;
}

#########################################################
# Ruby Program の読み込み
#########################################################
# RubyParser を利用して，Ruby のソースからS式を得る
sub generate_ruby_s_expression{
    my ($self, $ruby_file) = @_;

    croak "No $ruby_file." if(!-f $ruby_file);
    my $fh = FileHandle->new($ruby_file, O_RDONLY);
    croak "Cannot open $ruby_file." if(!defined($fh));
    my $ruby_source = join('', $fh->getlines());
    $fh->close();

    print STDERR "DEBUG: $ruby_source\n" if($DEBUG >= DEBUG_GENERATE_S_EXPRESSION);
    $ruby_source =~ s/"/\\"/g;

    my $tmp_file = TMP_DIR . $$;
    unlink($tmp_file) if(-f $tmp_file);
    my $tmp_fh = FileHandle->new($tmp_file, O_WRONLY|O_CREAT);
    $tmp_fh->printf("require 'ruby_parser'\nstring = \"%s\"\nprint(RubyParser.new.parse(string))\n", $ruby_source);
    $tmp_fh->close();

    open(COMMAND, $CONFIG{RUBY} . " $tmp_file|") or croak "Cannot execute.";
    my $s_expression_string = "";
    while(my $line = <COMMAND>){
	$s_expression_string .= $line;
    }
    close(COMMAND);

    return $s_expression_string;
}

# RubyParser を利用して，Ruby のソースからS式を得る
sub generate_ruby_s_expression_from_string{
    my ($self, $ruby_source) = @_;

    print STDERR "DEBUG: $ruby_source\n" if($DEBUG >= DEBUG_GENERATE_S_EXPRESSION);
    $ruby_source =~ s/"/\\"/g;

    my $tmp_file = TMP_DIR . $$;
    unlink($tmp_file) if(-f $tmp_file);
    my $tmp_fh = FileHandle->new($tmp_file, O_WRONLY|O_CREAT);
    $tmp_fh->printf("require 'ruby_parser'\nstring = \"%s\"\nprint(RubyParser.new.parse(string))\n", $ruby_source);
    $tmp_fh->close();

    open(COMMAND, $CONFIG{RUBY} . " $tmp_file|") or croak "Cannot execute.";
    my $s_expression_string = "";
    while(my $line = <COMMAND>){
	$s_expression_string .= $line;
    }
    close(COMMAND);

    return $s_expression_string;
}

#########################################################
# parse
#########################################################
# Ruby ソースファイル -> 内部表現
sub parse_ruby_file{
    my ($self, $ruby_file) = @_;

    # ファイルの読み込み
    croak "No $ruby_file." if(!-f $ruby_file);
    my $fh = FileHandle->new($ruby_file, O_RDONLY);
    croak "Cannot open $ruby_file." if(!defined($fh));
    my $ruby_source = join('', $fh->getlines());
    $fh->close();

    $ruby_source =~ s/"/\\"/g;

    return $self->parse_ruby_source($ruby_source);
}

# Ruby ソースコードの文字列 -> 内部表現
sub parse_ruby_source{
    my ($self, $ruby_source) = @_;

    my $s_string = $self->generate_ruby_s_expression_from_string($ruby_source);
    return $self->parse_s_expression($s_string);
}

# - S式 -> 内部表現
# 参考: http://blog.livedoor.jp/dankogai/archives/50816517.html

# S式の処理
# - 但し，RubyParse の出力に特化
# s(:defn, ....)
# sub parse{
#     my ($self, $str) = @_;

#     return $self->parse_s_expression($str);
# }

sub parse_s_expression{
    my ($self, $str) = @_;
    
    print STDERR "parse_s_expression: $str\n" if($DEBUG >= DEBUG_PARSE_S_EXPRESSION);
    # (以下の正規表現はまだ調整の余地有り)
    if($str =~ /^\s*s\((:\w+),\s*(\S.*)\)\s*$/si){
	# 述語
	my %hash = ();
	$hash{type}      = TYPE_PREDICATE;
	$hash{predicate} = $1;
	$hash{rest}      = $self->parse_arguments($2);
	return \%hash;
    }elsif($str =~ /^\s*s\((:\w+)\)\s*$/si){
	# 述語 (引数無し)
	my %hash = ();
	$hash{type}      = TYPE_PREDICATE;
	$hash{predicate} = $1;
	$hash{rest}      = [];
	return \%hash;
    }else{
	croak "ERROR: parse_s_expression ($str).";
    }
}

# - s(:..., 以降の引数部分
# - 引数に s式が含まれる場合有り
sub parse_arguments{
    my ($self, $str) = @_;

    print STDERR "parse_arguments: $str\n" if($DEBUG >= DEBUG_PARSE_S_EXPRESSION);    
    my @arguments = ();
    while($str =~ s/^((s\(:\w+)|([^,\)]+))//s){
	# print STDERR "parse_arguments (in): $str\n";    
	my $token = $MATCH;
	# print STDERR "parse_arguments-token: $token\n";    
	if($token =~ /^s\(/){
	    # s式(というかリスト)

	    # 括弧の終了までを取り出す
	    my $nest = 1;
	    my $pos;
	    for($pos = 0; $pos < length($str); $pos++){
		my $c = substr($str, $pos, 1);
		if($c eq '('){
		    $nest++;
		}elsif($c eq ')'){
		    $nest--;
		}
		last if($nest == 0)
	    }
	    my $rest_of_list = substr($str, 0, $pos + 1);
	    my $list_string  = $token . $rest_of_list;
	    $str = substr($str, $pos + 1);
	    push(@arguments, $self->parse_s_expression($list_string));
	}elsif($token =~ /^:(\S+)/){
	    # シンボル
	    push(@arguments, $self->generate_symbol($1));
	}else{
	    # リテラル
	    my %hash = ();
	    $hash{type}   = TYPE_LITERAL;
	    $hash{literal} = $1;
	    push(@arguments, \%hash);
	}
	$str =~ s/^\s*,\s*//s;

	# print STDERR "parse_arguments (arguments-token: $token\n";    
    }
    return \@arguments;
}

#########################################################
# 生成
#########################################################
sub generate_predicate{
    my ($self, $predicate, $rest_ref) = @_;

    my %hash = ();
    $hash{type}      = TYPE_PREDICATE;
    $hash{predicate} = $predicate;
    $hash{rest}      = $rest_ref;

    return \%hash;
}

sub generate_symbol{
    my ($self, $symbol) = @_;

    # シンボル
    my %hash      = ();
    $hash{type}   = TYPE_SYMBOL;
    $hash{symbol} = $symbol;

    return \%hash;
}

#########################################################
# reverse parse (S式)
#########################################################
# 内部表現からS式に変換
sub s_reverse_parse{
    my ($self, $hash_ref) = @_;

    # 一行毎の配列を改行でくっつけるのみ
    return join("\n", $self->s_reverse_parse_predicate($hash_ref));
}

# 節について
# - 最終的に一連の文字列にするまでは，1行単位で扱う
# - 行末の改行は入れない
sub s_reverse_parse_predicate{
    my ($self, $hash_ref) = @_;

    my @line_col = ();

    # predicate
    push(@line_col, "s(" . $hash_ref->{predicate});

    my $num_of_rest = scalar(@{$hash_ref->{rest}});
    foreach my $rest_hash_ref (@{$hash_ref->{rest}}){
	# 最後の要素でない場合に，直前の行末にカンマをつける
	$line_col[-1] .= ',' if($num_of_rest > 0);

	# 要素毎の処理
	my $rest_type = $rest_hash_ref->{type};
	if($rest_type eq TYPE_PREDICATE){
	    push(@line_col, map{INDENT . $_} $self->s_reverse_parse_predicate($rest_hash_ref));
		
	}elsif($rest_type eq TYPE_LITERAL){
	    push(@line_col, INDENT . $self->s_reverse_parse_literal($rest_hash_ref));
	}else{
	    push(@line_col, INDENT . $self->s_reverse_parse_symbol($rest_hash_ref));
	}
	$num_of_rest = $num_of_rest - 1;
    }
    push(@line_col, " )");

    return @line_col;
}

#
sub s_reverse_parse_symbol{
    my ($self, $hash_ref) = @_;

    return ':' . $hash_ref->{symbol};
}

#
sub s_reverse_parse_literal{
    my ($self, $hash_ref) = @_;

    return $hash_ref->{literal};
}

#########################################################
# reverse parse (Ruby)
#########################################################
# 内部表現 -> Ruby
sub reverse_parse{
    my ($self, $hash_ref) = @_;

    if($hash_ref->{type} eq TYPE_LITERAL){
	return $self->reverse_parse_literal($hash_ref);
    }elsif($hash_ref->{type} eq TYPE_SYMBOL){
	return $self->reverse_parse_symbol($hash_ref);
    }else{
	# predicate
	if($hash_ref->{predicate} eq ':defn'){
	    # 一行毎の配列を改行でくっつけるのみ
	    return join("\n", $self->reverse_parse_define($hash_ref));
	}else{
	    return $self->reverse_parse_predicate_scalar($hash_ref);
	}
    }
}

# メソッド定義 (:defn)
# def method_name(arg1, arg2, ...)
#   ...
# end
# - ruby_parser の version の違いなのか，出力される
#   S式が変わったため一部修正
sub reverse_parse_define{
    my ($self, $hash_ref) = @_;
    
    # エラーチェック
    croak "ERROR: Not method definition!" if($hash_ref->{type} ne TYPE_PREDICATE || $hash_ref->{predicate} ne ':defn');

    my @line_col = ();
    
    # 宣言
    push(@line_col, sprintf("def %s(%s)",
			    $self->reverse_parse_symbol($hash_ref->{rest}->[0]),
			    $self->reverse_parse_arguments($hash_ref->{rest}->[1]))
	);

    # メソッドの定義内容
    for(my $i = 2; $i < scalar(@{$hash_ref->{rest}}); $i++){
	my $rest_hash_ref = $hash_ref->{rest}->[$i];
	push(@line_col,
	     map{INDENT . $_} $self->reverse_parse_predicate_list($rest_hash_ref)
	    );
    }
    push(@line_col, 'end');

    # 終了
    return @line_col;
}

# 引数 (:args)
sub reverse_parse_arguments{
    my ($self, $hash_ref) = @_;
    
    return join(', ', map{$self->reverse_parse_symbol($_)} @{$hash_ref->{rest}});
}

# シンボル (:symbol)
sub reverse_parse_symbol{
    my ($self, $hash_ref) = @_;

    return $hash_ref->{symbol};
}

# 数値など (:lit)
sub reverse_parse_literal{
    my ($self, $hash_ref) = @_;

    # print STDERR Data::Dumper->Dump([$hash_ref]);
    return $hash_ref->{rest}->[0]->{literal};
}

# スコープ (:scope)
# - (必ず block 1個?)
sub reverse_parse_scope{
    my ($self, $hash_ref) = @_;

    my @line_col = ();

    foreach my $rest_hash_ref (@{$hash_ref->{rest}}){
	push(@line_col, $self->reverse_parse_block($rest_hash_ref));
    }
    
    return @line_col
}

# ブロック (:block)
# - (中身は様々だが... 基本的には predicate?)
# - 一行毎の配列で返す
sub reverse_parse_block{
    my ($self, $hash_ref, $indent) = @_;

    my @line_col = ();

    foreach my $rest_hash_ref (@{$hash_ref->{rest}}){
	push(@line_col,
	     $self->reverse_parse_predicate_list($rest_hash_ref, 'reverse_parse_block')
	     );
    }

    return @line_col;
}

# 代入式 (:lasgn)
# - for 文では左辺相当だけが現れることもある模様
sub reverse_parse_assignment{
    my ($self, $hash_ref) = @_;

    # 左辺
    my $lhs        = $hash_ref->{rest}->[0];
    my $lhs_symbol = $self->reverse_parse_symbol($lhs);
    return $lhs_symbol if(!exists($hash_ref->{rest}->[1]));

    # 右辺
    my $rhs        = $hash_ref->{rest}->[1];
    my $rhs_string = $self->reverse_parse_predicate_scalar($rhs);

    return sprintf("%s = %s", $lhs_symbol, $rhs_string);
}

# 式? (:call)
# - 演算子 a > 3
# - メソッド a.push(3)
sub reverse_parse_call{
    my ($self, $hash_ref) = @_;

    # 左辺
    my $left_term = $hash_ref->{rest}->[0];
    my $left_string  = '';
    if(defined($left_term) && not $self->is_nil($left_term)){
	$left_string = $self->reverse_parse($left_term);
    }

    # 演算子/メソッド
    my $operator  = $hash_ref->{rest}->[1];
    my $operator_string = $self->reverse_parse($operator);

    # 右辺
    my $num_of_right_term = scalar(@{$hash_ref->{rest}});
    my @right_string_col = ();
    if($num_of_right_term > 2){
	for(my $i = 2; $i < $num_of_right_term; $i++){
	    my $right_term = $hash_ref->{rest}->[$i];
	    my $right_string = $self->reverse_parse($right_term);
	    push(@right_string_col, $right_string) 
		if(defined($right_string) && $right_string ne '');
	}
    }

    # 返り値となる文字列
    my $string = $left_string;

    if($operator->{symbol} =~ /^[\-\+\*\%\^><=]{1,3}$/){
	#
	# 演算子の場合
	#
	if($left_string ne ''){
	    # 空白を入れる
	    $string .= ' ';
	}
	$string .= $operator_string;
	if(scalar(@right_string_col)){
	    # 空白を入れる
	    $string .= ' '
	}
	$string .= join(' ', @right_string_col);
    }elsif($operator->{symbol} eq '[]'){
	# 配列
	$string .= sprintf("[%s]", join(' ', @right_string_col));
    }else{
	#
	# メソッドの場合
	#
	if($left_string ne ''){
	    # ピリオド
	    $string .= '.';
	}
	$string .= $operator_string;

	# 引数がある場合
	if(scalar(@right_string_col)){
	    # 複数の引数をカンマ区切り
	    if($operator_string eq 'p'){
		# p ではカッコをつけないことが多そう
		$string .= ' ' . join(', ', @right_string_col);
	    }else{
		$string .= '(' . join(', ', @right_string_col). ')';	
	    }
	}
    }

    return $string;
}
	
# 代入式の左辺 (:lvar)
# - 必ず symbol?
# - 配列など変数の型によって処理を変更する必要が出てくるか
sub reverse_parse_lvar{
    my ($self, $hash_ref) = @_;

    return $self->reverse_parse_symbol($hash_ref->{rest}->[0]);
}

# 引数リスト? (:arglist)
sub reverse_parse_arglist{
    my ($self, $hash_ref) = @_;

    my @arglist_col = ();
    foreach my $rest_hash_ref (@{$hash_ref->{rest}}){
	push(@arglist_col, $self->reverse_parse($rest_hash_ref));
    }

    return join(', ', @arglist_col);
}

# if文 (:if)
sub reverse_parse_if{
    my ($self, $hash_ref) = @_;

    #
    # if
    #
    my $if_clause        = $hash_ref->{rest}->[0];
    my $if_clause_string = 
	$self->reverse_parse_predicate_scalar($if_clause, 'reverse_parse_if:if');
    my @line_col = ();
    # (条件式の後ろの then は省略可能)
    push(@line_col, sprintf("if %s then", $if_clause_string)); 

    #
    # then
    #
    my $then_clause = $hash_ref->{rest}->[1];
    push(@line_col, 
	 map{INDENT . $_}
	 $self->reverse_parse_predicate_list($then_clause, 'reverse_parse_if:then'));

    if(!exists($hash_ref->{rest}->[2])){
	push(@line_col, 'end');
	return @line_col;
    }

    #
    # else
    #
    push(@line_col, 'else');

    my $else_clause = $hash_ref->{rest}->[2];
    push(@line_col, 
	 map{INDENT . $_}
	 $self->reverse_parse_predicate_list($else_clause, 'reverse_parse_if:then'));

    push(@line_col, 'end');
    return @line_col;
}

# for文 (:for)
# s(:for, 
#   s(:dot2, s(:lit, 1), s(:lvar, :a)), 
#   s(:lasgn, :i),
#   s(:lasgn, 
#     :ans, 
#     s(:call, s(:lvar, :ans), :+, s(:arglist, s(:lvar, :a)))
#   )
# )
sub reverse_parse_for{
    my ($self, $hash_ref) = @_;

    my @line_col = ();

    # 繰返しの条件部分
    my $var          = $hash_ref->{rest}->[1];
    my $var_string   = $self->reverse_parse_assignment($var);
    my $range        = $hash_ref->{rest}->[0];
    my $range_string = $self->reverse_parse_predicate_scalar($range);
    push(@line_col, sprintf("for %s in %s", $var_string, $range_string));

    # 繰返しの中身
    my $loop           = $hash_ref->{rest}->[2];
    push(@line_col,
	 map{INDENT . $_}
	 $self->reverse_parse_predicate_list($loop));

    push(@line_col, 'end');
    
    return @line_col;
}


# while文 (:while) (Mon Nov  5 17:52:00 2012)
sub reverse_parse_while{
    my ($self, $hash_ref) = @_;

    # 条件
    my $condition_clause        = $hash_ref->{rest}->[0];
    my $condition_clause_string = 
	$self->reverse_parse_predicate_scalar($condition_clause, 'reverse_parse_while:condition');
    my @line_col = ();
    # (条件式の後ろの do は省略可能)
    push(@line_col, sprintf("while (%s) do", $condition_clause_string)); 

    #
    # Block(?)
    #
    push(@line_col, 
	 map{INDENT . $_}
	 $self->reverse_parse_block($hash_ref->{rest}->[1], 'reverse_parse_condition:block'));
    
    push(@line_col, 'end');
    return @line_col;
}

sub does_return_line_col{
    my ($self, $predicate) = @_;

    return ($predicate =~ /^:(block|if|for)$/i);
}

# reverse_parse の debug 用
sub not_yet_implemented_reverse_parse{
    my ($self, $hash_ref, $predicate, $method_name) = @_;

    return if($DEBUG < DEBUG_REVERSE_PARSE_RUBY);

    printf(STDERR "DEBUG: Not yet implemented \"%s\" (%s)\n",
	   $predicate, $method_name);

    return if($DEBUG < DEBUG_INTERNAL_DATA);

    printf(STDERR "DEBUG: %s\n", Data::Dumper->Dump([$hash_ref]));

}

# 範囲 (:dot2)
#   s(:dot2, s(:lit, 1), s(:lvar, :a)), 
sub reverse_parse_dot2{
    my ($self, $hash_ref) = @_;

    my $from_string = 
	$self->reverse_parse_predicate_scalar($hash_ref->{rest}->[0], 'reverse_parse_dot2:from');
    my $to_string = 
	$self->reverse_parse_predicate_scalar($hash_ref->{rest}->[1], 'reverse_parse_dot2:to');
    return sprintf("%s .. %s", $from_string, $to_string);

}

# 配列 (:array)
sub reverse_parse_array{
    my ($self, $hash_ref) = @_;

    my @array = ();
    foreach my $rest_hash_ref (@{$hash_ref->{rest}}){
	push(@array, $self->reverse_parse($rest_hash_ref));
    }

    return '[' . join(', ', @array) . ']';
}

# 配列の要素への代入 (:attraasgn) (Mon Nov 26 13:50:38 2012)
sub reverse_parse_array_assignment{
    my ($self, $hash_ref) = @_;

    # print STDERR Data::Dumper->Dump([$hash_ref->{rest}->[0]]);

    # 左辺
    my $lhs        = $hash_ref->{rest}->[0];
    my $lhs_symbol = $self->reverse_parse($lhs);

    # 配列の添字
    my $index_ref  = $hash_ref->{rest}->[2];
    my $index_str  = $self->reverse_parse($index_ref);

    # 右辺
    my $rhs        = $hash_ref->{rest}->[3];
    my $rhs_str    = $self->reverse_parse($rhs);

    return sprintf("%s[%s] = %s", $lhs_symbol, $index_str, $rhs_str);
}

# 結果がスカラー形式のもの
sub reverse_parse_predicate_scalar{
    my ($self, $clause, $caller_name) = @_;

    my $predicate = $clause->{predicate};
    my $string;
    if(exists($REVERSE_PARSE_METHOD_HASH{$predicate})){
	my $method = $REVERSE_PARSE_METHOD_HASH{$predicate};
	$string = $self->$method($clause);

#  block が与えられた場合の扱いは要検討
# 	if($self->does_return_line_col($else_clause_predicate)){
# 	    push(@line_col, map{INDENT . $_} $self->$method($else_clause));
# 	}else{
# 	    push(@line_col, INDENT . $self->$method($else_clause));
# 	}

    }else{
	$self->not_yet_implemented_reverse_parse($clause, $predicate, $caller_name);
	$string = '...';
    }
    
    return $string;
}

# 結果がリスト形式のもの
sub reverse_parse_predicate_list{
    my ($self, $hash_ref, $caller_name) = @_;

    my $predicate = $hash_ref->{predicate};
    my @col = ();
    if(exists($REVERSE_PARSE_METHOD_HASH{$predicate})){
	my $method = $REVERSE_PARSE_METHOD_HASH{$predicate};
	push(@col, $self->$method($hash_ref));
    }else{
	$self->not_yet_implemented_reverse_parse($hash_ref, $predicate, $caller_name);
	push(@col, '...');
    }
    
    return @col;
}

# AND (Mon Nov 26 14:13:20 2012)
sub reverse_parse_and{
    my ($self, $hash_ref) = @_;

    # print STDERR Data::Dumper->Dump([$hash_ref->{rest}->[0]]);

    my @formula_str_col = ();
    my $i = 0;
    while(exists($hash_ref->{rest}->[$i])){
	push(@formula_str_col, $self->reverse_parse($hash_ref->{rest}->[$i]));
	$i++;
    }

    return join(' && ', @formula_str_col);
}

#########################################################
# testing
#########################################################
sub is_predicate{
    my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_PREDICATE);
}

sub is_symbol{
    my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_SYMBOL);
}

sub is_literal{
    my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_LITERAL);
}

sub is_literal_or_symbol{
    my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_LITERAL || $hash_ref->{type} eq TYPE_SYMBOL);
}

sub is_if{
    my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_PREDICATE && $hash_ref->{predicate} eq ':if');
}

sub is_for_loop{
    my ($self, $hash_ref) = @_;

    # print STDERR Data::Dumper->Dump([$hash_ref]);
    return ($hash_ref->{type} eq TYPE_PREDICATE && $hash_ref->{predicate} eq ':for');
}

sub is_while_loop{
    my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_PREDICATE && 
	    $hash_ref->{predicate} eq ':while');
}

sub is_loop{
    my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_PREDICATE && 
	    ($hash_ref->{predicate} eq ':for' ||
	     $hash_ref->{predicate} eq ':while'));
}

sub is_block{
    my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_PREDICATE &&
	    $hash_ref->{predicate} eq ':block');
}

sub is_method_definition{
    my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_PREDICATE &&
	    $hash_ref->{predicate} eq ':defn');
}

sub is_scope{
    my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_PREDICATE &&
	    $hash_ref->{predicate} eq ':scope');
}

# 代入式
sub is_assignment{
    my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_PREDICATE && $hash_ref->{predicate} eq ':lasgn');
}

#
sub is_call{
    my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_PREDICATE && $hash_ref->{predicate} eq ':call');
}

# nil ... 内部的には literal?
sub is_nil{
    my ($self, $hash_ref) = @_;
    
    return ($hash_ref->{type} eq TYPE_LITERAL && $hash_ref->{literal} eq 'nil');
}

# scope, block, for, if
sub has_sentences{
   my ($self, $hash_ref) = @_;

    return ($hash_ref->{type} eq TYPE_PREDICATE && 
	    $hash_ref->{predicate} =~ /^:(defn|scope|block|for|if)$/i);
}

# 配列参照
# - c[i] のような形式
sub is_array_reference{
    my ($self, $hash_ref) = @_;

    return $self->is_call($hash_ref) && $hash_ref->{rest}->[1]->{symbol} eq '[]';
}

#########################################################
# copying
#########################################################
sub deep_copy{
    my ($self, $hash_ref) = @_;

    my %new_hash = ();
    $new_hash{type} = $hash_ref->{type};
    if($hash_ref->{type} eq TYPE_PREDICATE){
	$new_hash{predicate} = $hash_ref->{predicate};
	my @arguments = ();
	map{push(@arguments, $self->deep_copy($_))} @{$hash_ref->{rest}};
	$new_hash{rest} = \@arguments;
    }elsif($hash_ref->{type} eq TYPE_LITERAL){
	$new_hash{literal} = $hash_ref->{literal};
    }elsif($hash_ref->{type} eq TYPE_SYMBOL){
	$new_hash{symbol} = $hash_ref->{symbol};
    }else{
	croak "ERROR: deep_copy (" . Data::Dumper->Dump([$hash_ref]) . ").";
    }

    return \%new_hash;
}

#########################################################
# 比較 comparison
#########################################################
sub is_same_as{
    my ($self, $code_a, $code_b) = @_;

    if($self->is_symbol($code_a) && $self->is_symbol($code_b)){
	return ($code_a->{symbol} eq $code_b->{symbol});
    }elsif($self->is_literal($code_a) && $self->is_literal($code_b)){
	return ($code_a->{literal} == $code_b->{literal});
    }elsif($self->is_predicate($code_a) && $self->is_predicate($code_b)){
	return 0 if($code_a->{predicate} ne $code_b->{predicate});
	
	my $num_of_rest_a = scalar(@{$code_a->{rest}});
	my $num_of_rest_b = scalar(@{$code_b->{rest}});

	return 0 if($num_of_rest_a != $num_of_rest_b);
	for(my $i = 0; $i < $num_of_rest_a; $i++){
	    my $clause_a = $code_a->{rest}->[$i];
	    my $clause_b = $code_b->{rest}->[$i];

	    return 0 if(!defined($clause_a) || !defined($clause_b));
	    my $result = $self->is_same_as($clause_a, $clause_b);
	    return 0 if(!$result);
	}
    }

    return 1;
}

#########################################################
# 定数
#########################################################
sub index_of_contents_of_for_loop{
    return 2;
}

sub index_of_then_clause{
    return 1;
}

sub index_of_else_clause{
    return 2;
}

#########################################################
# 参照
#########################################################
# メソッド名を文字列で返す
sub get_method_name{
    my ($self, $hash_ref) = @_;

    if(!$self->is_method_definition($hash_ref)){
	print STDERR "Not method definition." if($DEBUG >= DEBUG_INTERNAL_DATA);
	return undef;
    }
    return $self->reverse_parse_symbol($hash_ref->{rest}->[0]);
}

#########################################################
# 操作
#########################################################

###############
# for
# (sample)
#  for i in 1 .. a
#    ...
# ->
#    s(:for,
#         s(:dot2,
#           s(:lit,
#             1
#           ),
#           s(:lvar,
#             :a
#           )
#         ),
#         s(:lasgn,
#           :i
#         ),
#         s( ...

sub get_contents_of_for_loop{
   my ($self, $hash_ref) = @_;

   return $hash_ref->{rest}->[2];
}

sub get_control_variable_of_for_loop{
   my ($self, $hash_ref) = @_;

   return $hash_ref->{rest}->[1]->{rest}->[0];
}

sub get_max_range_of_for_loop{
   my ($self, $hash_ref) = @_;

   my $dot2 = $hash_ref->{rest}->[0];
   return $dot2->{rest}->[1]->{rest}->[0];
}

###############
# if-then
sub get_if_clause{
   my ($self, $hash_ref) = @_;

   return $hash_ref->{rest}->[0];
}

sub get_then_clause{
   my ($self, $hash_ref) = @_;

   return $hash_ref->{rest}->[1];
}

sub get_else_clause{
   my ($self, $hash_ref) = @_;

   return $hash_ref->{rest}->[2];
}

###############
# その他

sub get_all_sentences{
   my ($self, $hash_ref) = @_;

   return @{$hash_ref->{rest}};
}

sub replace_sentence_at{
    my ($self, $hash_ref, $new_sentence, $index) = @_;

    print STDERR "DEBUG: replace_sentence_at $index\n";
    if($self->is_block($new_sentence)){
	print STDERR "DEBUG: is_block at $index " . Data::Dumper->Dump([$new_sentence]) .  

	my @col = ();
	for(my $i = 0; $i < scalar(@{$hash_ref->{rest}}); $i++){
	    if($i == $index){
		push(@col, @{$new_sentence->{rest}});
	    }else{
		push(@col, $hash_ref->{rest}->[$i]);
	    }
	}
	$hash_ref->{rest} = \@col;
    }else{
	print STDERR "DEBUG: is not block ($index)\n";
	$hash_ref->{rest}->[$index] = $new_sentence;
    }
}

# 変数の置換 (Mon Mar  5 20:13:25 2012)
sub replace_variable_into{
    my ($self, $hash_ref, $old_var, $new_var) = @_;

    printf(STDERR "DEBUG: replace_variable_into (%s -> %s)\n",
	   $old_var->{symbol}, $new_var->{symbol});
    my $is_changed = 0;
    if($hash_ref->{type} eq TYPE_PREDICATE){
	my @new_arguments = ();
	foreach my $rest_hash (@{$hash_ref->{rest}}){
	    my $new_hash;
	    if($rest_hash->{type} eq TYPE_SYMBOL &&
	       $rest_hash->{symbol} eq $old_var->{symbol}){
		$new_hash = $self->deep_copy($new_var);
		$is_changed = 1;
	    }
	    if(defined($new_hash)){
		push(@new_arguments, $new_hash);
	    }else{
		my ($answer_hash_ref, $result) = $self->replace_variable_into($rest_hash, $old_var, $new_var);
		push(@new_arguments, $answer_hash_ref);
		$is_changed = 1 if($result);
	    }
	}
	$hash_ref->{rest} = \@new_arguments;
    }

    return ($hash_ref, $is_changed);
}

1;

# my $str = "s(:defn, :a1, s(:args, :a), s(:scope, s(:block, s(:lasgn, :ans, s(:lit, 0)), s(:if, s(:call, s(:lvar, :a), :>, s(:arglist, s(:lit, 3))), s(:lasgn, :ans, s(:call, s(:lvar, :ans), :+, s(:arglist, s(:lvar, :a)))), s(:lasgn, :ans, s(:call, s(:lvar, :ans), :-, s(:arglist, s(:lvar, :a))))), s(:lasgn, :scope, s(:array, s(:lit, 1), s(:lit, 3))), s(:call, nil, :p, s(:arglist, s(:lvar, :ans))))))";

# print STDERR "DEBUG: (original) $str\n";
# print Data::Dumper->Dump([parse_s_expression($str)]);

