# -*- coding: utf-8 -*-
# 最大値
def arr05(c)
  n = c.size
  m = c[0]
  for i in (1..n-1) do
    if m < c[i] then
      m = c[i]
    end
  end
  p m
end

# 動作確認
c = [1, 8, 6, 2, 3, 4]
p c 
arr05(c)

