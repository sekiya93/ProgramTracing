#!/usr/bin/perl 

use strict;

use lib '/usr/local/plack/tracing/lib';

use ExamResponse::File;

use Data::Dumper;

#########################
# 読込み
#########################
# my $exam_id   = 'id001';
# my @response_col = ExamResponse::File->get_list($exam_id);

# foreach my $response (@response_col){
#     printf("userid: %s, date: %s, score: %d\n", 
# 	   $response->userid(),
# 	   $response->date(),
# 	   $response->score());
# }

#########################
# 書き込み
#########################
my $response = ExamResponse::File->new();
$response->exam_id('id000');
$response->userid('sekiya');
$response->realm('local');
$response->fullname('関谷 貴之');
$response->set_response(
    1, 
    [2, 0, 1, 0, 2],
    1,
    ["answer"]
    );

$response->save();

print Data::Dumper->Dump([$response]);

# my $answer_id = 'id001_gakugei_b112222_2012-05-31_1501_35';

# my $exam_response = ExamResponse::File->get($exam_id, $answer_id);

# print Data::Dumper->Dump([$exam_response]);




