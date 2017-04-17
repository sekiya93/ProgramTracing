#!/usr/bin/perl 
############################################################
#
# update_exam_answer.pl
#
# Time-stamp: <2012-11-05 18:51:53 sekiya>
#
# - Usage: $0 exam_id
#
# - 事前に変換(生成)しておいた誤答用コードに基づいて，
#   解を出力
#
############################################################

use strict;

use constant{
    CONFIG_DIR        => '/usr/local/plack/tracing/conf',
};

use lib '/usr/local/plack/tracing/lib';

use Data::Dumper;
use Config::Simple;
my %CONFIG;
my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

use Exam::File;
use ConverterEngine;
my $CONVERTER = ConverterEngine->new();

# 処理対象の試験
my $exam_id = $ARGV[0];
if(!defined($exam_id)){
    die "Usage: $0 exam_id";
}

my $exam = Exam::File->get_by_id($exam_id);
if(!defined($exam)){
    die "No Exam ($exam_id)";
}

# 指定された試験の読み込み
my ($answer_data_column_names_ref, $answer_data_col_ref, $number_of_questions_ref) = $exam->read_exam_answer_file();

# 再評価?
foreach my $quest (@{$answer_data_col_ref}){
    # print STDERR Data::Dumper->Dump([$answer_data]);
    $quest = $CONVERTER->evaluate_answer_item($quest);
    $exam->set_quest_data($quest);
}




