# -*- coding: utf-8 -*-
# ローテーション
# - 逐次隣を入れ替えながら，最終的に先頭の要素が
#   最後に移動
def arr01(c)
  n = c.size
  for i in 0..n-2
    t      = c[i]
    c[i]   = c[i+1]
    c[i+1] = t
  end
  p c
end

c = [1, 5, 7, 8]
p c
arr01(c)
arr01(c)
