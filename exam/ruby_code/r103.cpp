#include <iostream>
using namespace std;
int r103(int n) {
  int s = n;
  for(int i=1; i<=n-1; i++) s = s + r103(i);
  return s;
}
