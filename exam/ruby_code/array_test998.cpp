#include <iostream>
using namespace std;
int array_test998(int c[3][3]) {
  int x = c[2][1];
  int y = c[0][2];
  int z = c[x][2];
  int w = c[0][y];
  return c[w][z];
}
