# -*- coding: utf-8 -*-
# ITiCSE2004 WG の実施した試験
# [Lister:2004:MSR:1044550.1041673] 
# - Question 2 のコードを修正
def arr10(c1, c2)
  i1 = c1.length - 1
  i2 = c2.length - 1
  count = 0
  while (i1 > 0 && i2 > 0) do
    if c1[i1] == c2[i2] then
      count = count + 1
      i1 = i1 - 1
      i2 = i2 - 1
    elsif c1[i1] < c2[i2] then
      i2 = i2 - 1
    else
      # c1[i1] > c2[i2] 
      i1 = i1 - 1
    end
  end
  p count
end

c1 = [1, 2, 4, 7]
c2 = [1, 2, 5, 7]
arr10(c1, c2)
