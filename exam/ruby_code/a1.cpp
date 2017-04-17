#include <iostream>
using namespace std;
int a1(int a) {
  int ans = 0;
  if (a > 3) ans = ans + a;
  else ans = ans - a;
  return ans;
}
