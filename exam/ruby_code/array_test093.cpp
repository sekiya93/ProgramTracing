#include <iostream>
using namespace std;
int array_test093(int c[]) {
  int x = c[3];
  int y = c[3];
  c[y] = x / y;
  int z = c[x];
  return c[z];
}

