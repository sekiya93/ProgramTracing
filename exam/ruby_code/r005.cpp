#include <iostream>
using namespace std;
int b[] = {1, 2, 3, 4};
int r005(int i) {
  if (i == 0) return b[0];
  else return r005(i-1) + b[i];
}
