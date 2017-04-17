#include <iostream>
using namespace std;
int a5(int a) {
  int ans = 0;
  for(int i=1; i<=a; i++)
    if(a > 3) ans = ans + a;
    else ans = ans - a;
  return ans;
}
