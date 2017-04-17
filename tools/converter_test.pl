#!/usr/bin/perl 

use strict;

use constant{
    CONFIG_DIR        => '/usr/local/plack/tracing/conf',
};

use lib '/usr/local/plack/tracing/lib';

use Exam::File;
use ConverterEngine;

use Data::Dumper;

use Config::Simple;
my %CONFIG;
my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

my ($target, $input) = @ARGV;

die "No file ($target)." if(!defined($target) || !-f $target);
# my $base = $target;
# if($target =~ /\/([^\/]+\.rb)/){
#     $base = $1;
# }

my $CONVERTER = ConverterEngine->new();

my $output = $CONVERTER->evaluate_ruby_code($target, $input);

printf("answer: %d\n", $output)

# my $exam_id = 'id001';
# my $exam = Exam::File->get_by_id($exam_id);

# my $converter_hash_ref = $CONVERTER->get_converter_data();
# while(my ($label, $data) = each(%{$converter_hash_ref})){
#     my $converted_dir = sprintf("%s/%s", 
# 				$CONFIG{CONVERTED_DIR},
# 				$base);
#     mkdir($converted_dir) if(!-d $converted_dir);

#     my $command = sprintf("%s/%s %s %s/%s",
# 			  $CONFIG{TOP_DIR},
# 			  'converter/' . $data->{script},
# 			  $target,
# 			  $converted_dir,
# 			  $label);
#     print STDERR "DEBUG: $command\n";
# }


# # 指定された試験の読み込み
# my ($answer_data_column_names_ref, $answer_data_col_ref) = 
#     $exam->read_exam_answer_file();


# foreach my $data (@{$answer_data_col_ref}){
#     $data->{input} = $data->{input} + 1;
#     # print STDERR Data::Dumper->Dump([$data]);
#     my $answer = $CONVERTER->evaluate_answer_item($data);
#     print STDERR Data::Dumper->Dump([$answer]);
# }




