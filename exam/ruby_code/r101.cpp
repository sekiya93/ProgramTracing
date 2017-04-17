#include <iostream>
using namespace std;
int r101(int n) {
  if(n < 1) return 1;
  else return r101(n-1) + n;
}
