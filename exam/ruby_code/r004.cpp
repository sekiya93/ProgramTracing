#include <iostream>
using namespace std;
int a[] = {2, 15, 4, 8, 1};
int r004(int i) {
  if (i == 0) return a[0];
  else {
    int m = r004(i-1);
    if (m > a[i]) return m;
    else return a[i];
  }
}
