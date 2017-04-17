package PTDB::Schema;
use Teng::Schema::Declare;

table {
    name 'ptuser';
    pk 'id';
    columns qw(id userid password fullname fullname_ja mail_address realm register_date update_date);
};
table {
	name 'ptExam';
	pk 'id';
	columns qw(id name realm userid questions register_date update_date valid);
};
table {
	name 'ptRelation';
	pk 'id';
	columns qw(id exam_id question_id order register_date update_date valid);
};
table {
	name 'ptQuestion';
	pk 'id';
	columns qw(id code_file_name input answer userid type register_date update_date valid);
};
1;
