#include <iostream>
using namespace std;
int a9(int a) {
  int ans = 0;
  if (a > 3) 
    for(int i=1; i<=a; i++)
      ans = ans + a;
  else ans = ans - a;
  return ans;
}
