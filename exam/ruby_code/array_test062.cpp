#include <iostream>
using namespace std;
int array_test062(int c[]) {
  int x = c[2];
  int y = c[2];
  c[y] = x * y;
  int z = c[x];
  return c[z];
}
