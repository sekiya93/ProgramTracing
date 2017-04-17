#include <iostream>
using namespace std;
int a8(int a) {
  int ans = 0;
  for(int i=1; i<=a; i++) 
    if (i == 3) ans = ans + i;
    else ans = ans - i;
  return ans;
}
