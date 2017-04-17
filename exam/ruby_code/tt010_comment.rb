# -*- coding: utf-8 -*-
# 減らす
def tt010(c)
  i = 0
  q = 0
  while q != 3 do
    if c[i] == 0 then
      if q == 0 then
        q = 3
      else
        i = i - 1
        q = 2
      end
    else
      if q == 2 then
        c[i] = 0
        q = 3
      else
        i = i + 1
        q = 1
      end
    end
    printf("(q, i, c) = (%d, %d, %s)\n", q, i, c.to_s)
  end
  p c
end

tt010([1, 0, 0, 0, 0])
