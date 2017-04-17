#include <iostream>
using namespace std;
int r003(int n, int k) {
  if (k > n) return 0;
  else if (k == 0) return 1;
  else return r003(n-1, k-1) + r003(n-1, k);
}
