#include <iostream>
using namespace std;
int r107(int n) {
  if(n < 1) {
    return n;
  }
  return r107(n-2)+n+r107(n-1);
}
