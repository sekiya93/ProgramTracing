#!/usr/bin/perl 
############################################################
#
# generate_convetered_codes.pl
#
# Time-stamp: <2013-07-22 17:27:49 sekiya>
#
# - Usage: $0 target_code [LABEL ...]
#
# - 指定した Ruby コードを変換したコードを
#   所定の位置に保存する
# - LABEL を指定した場合は，指定したラベルに対応する
#   変換のみを実施する
#
############################################################

use strict;

use constant{
#    CONFIG_DIR        => '/usr/local/plack/tracing/conf',
     CONFIG_DIR        => 'conf',
};

#use lib '/usr/local/plack/tracing/lib';
use lib 'lib';

use Exam::File;
use ConverterEngine;

use Data::Dumper;

use Config::Simple;
my %CONFIG;
my $CONFIG_FILE = sprintf("%s/base.conf", CONFIG_DIR);
Config::Simple->import_from($CONFIG_FILE, \%CONFIG)
    or die Config::Simple->error();

# 変換対象のコード
my $target_code = $ARGV[0];
die "No file ($target_code)." if(!defined($target_code) || !-f $target_code);
my $base = $target_code;
if($target_code =~ /\/([^\/]+\.rb)/){
    $base = $1;
}
my $converted_dir = sprintf("%s/%s", 
			    $CONFIG{CONVERTED_DIR},
			    $base);
mkdir($converted_dir) if(!-d $converted_dir);

my $CONVERTER = ConverterEngine->new();
my $converter_hash_ref = $CONVERTER->get_converter_data();

shift(@ARGV);

# 変換器を指定した場合
if(scalar(@ARGV)){
    my $tmp_hash_ref = $converter_hash_ref;
    $converter_hash_ref = {};
    foreach my $label (@ARGV){
	if(exists($tmp_hash_ref->{$label})){
	    $converter_hash_ref->{$label} = $tmp_hash_ref->{$label};
	}
    }
}

my @converter_labels = keys(%{$converter_hash_ref});
################################################
# 変換
################################################
# 変換済みのコードを保持
# - $label -> converted_code_file
my %converted_hash = ();
foreach my $label1 (@converter_labels){
    my $data1 = $converter_hash_ref->{$label1};
    # 変換後のファイル1
    my $converted_file1 = sprintf("%s/%s",
				  $converted_dir,
				  $label1);
    unlink($converted_file1) if(-f $converted_file1);

    my $command1 = sprintf("%s/%s %s %s",
			  $CONFIG{TOP_DIR},
			  'converter/' . $data1->{script},
			  $target_code,
			  $converted_file1);
    print STDERR "DEBUG1: $command1\n";
    system($command1);

    # 変換に成功しなかった場合は，次の処理は行わない
    next if(!-f $converted_file1);
    $converted_hash{$label1} = $converted_file1;

    # 2回目の変換
    foreach my $label2 (@converter_labels){
	my $data2 = $converter_hash_ref->{$label2};
	# next if($label2 eq $label1); # 同じ処理を繰り返すことにももしかしたら意味がある？

	# 変換後のファイル2
	my $converted_file2 = sprintf("%s/%s-%s",
				      $converted_dir,
				      $label1,
				      $label2);
	unlink($converted_file2) if(-f $converted_file2);
	my $command2 = sprintf("%s/%s %s %s",
			       $CONFIG{TOP_DIR},
			       'converter/' . $data2->{script},
			       $converted_file1,
			       $converted_file2);
	print STDERR "DEBUG2:\t$command2\n";
	system($command2);

	# 変換に成功しなかった場合は，次の処理は行わない
	next if(!-f $converted_file2);
	$converted_hash{"$label1-$label2"} = $converted_file2;

	# 3回目の変換
	foreach my $label3 (@converter_labels){
	    my $data3 = $converter_hash_ref->{$label3};
	    # next if($label3 eq $label1);

	    # 変換後のファイル3
	    my $converted_file3 = sprintf("%s/%s-%s-%s",
					  $converted_dir,
					  $label1,
					  $label2,
					  $label3);
	    unlink($converted_file3) if(-f $converted_file3);
	    my $command3 = sprintf("%s/%s %s %s",
				   $CONFIG{TOP_DIR},
				   'converter/' . $data3->{script},
				   $converted_file2,
				   $converted_file3);
	    print STDERR "DEBUG3:\t\t$command3\n";
	    system($command3);

	    # 変換に成功しなかった場合は，次の処理は行わない
	    next if(!-f $converted_file3);
	    $converted_hash{"$label1-$label2-$label3"} = $converted_file3;
	}
    }
}





