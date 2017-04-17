#include <iostream>
using namespace std;
int a10(int a) {
  int ans = 0;
  if (a == 3) ans = ans + a;
  else 
    for(int i=1; i<=a; i++) 
      ans = ans - a;
  return ans;
}
