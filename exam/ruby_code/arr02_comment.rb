# -*- coding: utf-8 -*-
# ローテーションの逆
# - 逐次隣を入れ替えながら，最終的に末尾の要素が
#   先頭に移動
def arr02(c)
  n = c.size
  for i in 1..n-1 do
    t        = c[n-i]
    c[n-i]   = c[n-i-1]
    c[n-i-1] = t
  end
  p c
end

c = [1, 5, 7, 8, 6]
p c
arr02(c)
arr02(c)
