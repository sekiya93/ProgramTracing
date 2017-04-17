#include <iostream>
using namespace std;
void r105(int n) {
  cout << n << " ";
  if(n > 0) {
    r105(n-2);
    r105(n-1);
  }
}
