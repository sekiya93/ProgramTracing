#!/usr/bin/perl 
############################################################
#
# generate_exam_answer.pl
#
# Time-stamp: <2013-08-08 17:12:15 sekiya>
#
# - Usage: $0 exam_id
#
# - 事前に変換(生成)しておいた誤答用コードに基づいて生成
#   
#
############################################################

use strict;

use constant{
    CONFIG_DIR        => '/usr/local/plack/tracing/conf',
};

use lib '/usr/local/plack/tracing/lib';

my ($CONVERTER_DATA_FILE, $EXAM_ID, $TRANSPOSE);
use Getopt::Long qw(:config auto_help);
GetOptions(
    "converter=s" => \$CONVERTER_DATA_FILE,
    "exam_id=s"   => \$EXAM_ID,
    "transpose"   => \$TRANSPOSE,
    ) or exit 1;

die "No exam ID!" if(!defined($EXAM_ID));

=head1 SYNOPSIS

    ./generate_exam_answer_data.pl [--converter converter_data_file] --exam_id exam_id

=cut

use Data::Dumper;
use Config::Simple;
my %CONFIG;
my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

use ConverterEngine;
my $CONVERTER = ConverterEngine->new();
my $converter_data_ref = $CONVERTER->read_converter_file($CONVERTER_DATA_FILE);

use Utility;

use Exam::File;
my $exam = Exam::File->get_by_id($EXAM_ID);
if(!defined($exam)){
    die "No Exam ($EXAM_ID)";
}

# 指定された試験の読み込み
my ($answer_data_column_names_ref, $answer_data_col_ref, $number_of_questions_ref) = $exam->read_exam_answer_file();

# 再評価?
my @evaluated = ();
foreach my $quest (@{$answer_data_col_ref}){
    # print STDERR Data::Dumper->Dump([$answer_data]);
    $quest = $CONVERTER->evaluate_answer_item($quest, $converter_data_ref);
    push(@evaluated, $quest);
}

# 出力
if(defined($TRANSPOSE)){
    my @key_col = ('answer');
    push(@key_col, sort(keys(%{$converter_data_ref})));
	 
    foreach my $key (@key_col){
	my @col = ();
	foreach my $quest (@evaluated){
	    my $str;
	    if(exists($quest->{$key})){
		$str = Utility::value_to_string($quest->{$key});
		if($str =~ /,/){
		    $str = '"' . $str . '"';
		}
	    }else{
		$str = '-';
	    }
	    push(@col, $str);
	}
	printf("\"%s\",%s\n", $key, join(',', @col));
    }
}else{
    my @key_col = ('index','source','input','answer');
    push(@key_col, sort(keys(%{$converter_data_ref})));
    push(@key_col, 'type');

    $exam->dump(\@key_col, \@evaluated);
}                                
