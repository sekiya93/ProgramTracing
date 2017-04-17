#include <iostream>
using namespace std;
void r102(int n) {
  cout << n << " ";
  for(int i=1; i<=n-1; i++) r102(i);
}
