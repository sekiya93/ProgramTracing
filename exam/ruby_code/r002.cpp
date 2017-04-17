#include <iostream>
using namespace std;
int r002(int c) {
  if(c > 1) return c*r002(c-1);
 else return c;
}
