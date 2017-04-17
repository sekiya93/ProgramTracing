# -*- coding: utf-8 -*-
# ITiCSE2004 WG の実施した試験
# [Lister:2004:MSR:1044550.1041673] 
# - Question 1 のコードをアレンジ
def arr09(c, limit)
  n = c.size
  i = 0
  sum = 0
  while (sum < limit && i < n) do
    sum = sum + c[i]
    i = i + 1
  end
  p i
end

c = [2, 1, 4, 5, 7]
p c
arr09(c, 4)
