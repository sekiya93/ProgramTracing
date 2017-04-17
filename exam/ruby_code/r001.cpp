#include <iostream>
using namespace std;
int r001(int c) {
  if(c > 1) return r001(c/2);
  else return c;
}
