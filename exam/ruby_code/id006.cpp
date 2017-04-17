#include <iostream>
using namespace std;

int r101(int n) {
  if(n < 1) return 1;
  else return r101(n-1) + n;
}

void r102(int n) {
  cout << n << " ";
  for(int i=1; i<=n-1; i++) r102(i);
}

int r103(int n) {
  int s = n;
  for(int i=1; i<=n-1; i++) s = s + r103(i);
  return s;
}

int r002(int c) {
  if(c > 1) return c*r002(c-1);
 else return c;
}

int r001(int c) {
  if(c > 1) return r001(c/2);
  else return c;
}

void r105(int n) {
  cout << n << " ";
  if(n > 0) {
    r105(n-2);
    r105(n-1);
  }
}

int r107(int n) {
  if(n < 1) {
    return n;
  }
  return r107(n-2)+n+r107(n-1);
}

int a[] = {2, 15, 4, 8, 1};
int r004(int i) {
  if (i == 0) return a[0];
  else {
    int m = r004(i-1);
    if (m > a[i]) return m;
    else return a[i];
  }
}

int b[] = {1, 2, 3, 4};
int r005(int i) {
  if (i == 0) return b[0];
  else return r005(i-1) + b[i];
}

int r003(int n, int k) {
  if (k > n) return 0;
  else if (k == 0) return 1;
  else return r003(n-1, k-1) + r003(n-1, k);
}

int main() {
  cout << "r101=" << r101(3) << endl;
  cout << "r102=";
  r102(3);
  cout << endl;
  cout << "r103=" << r103(3) << endl;
  cout << "r002=" << r002(5) << endl;
  cout << "r001=" << r001(20) << endl;
  cout << "r105=";
  r105(4);
  cout << endl;
  cout << "r107=" << r107(5) << endl;
  cout << "r004=" << r004(4) << endl;
  cout << "r005=" << r005(3) << endl;
  cout << "r003=" << r003(5, 2) << endl;
}
