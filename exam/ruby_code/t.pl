for(my $i = 1; $i <= 10; $i++){
    system("cat 3.txt a$i.txt > a$i" . "_3.txt");
    system("cat 4.txt a$i.txt > a$i" . "_4.txt");
}
  
