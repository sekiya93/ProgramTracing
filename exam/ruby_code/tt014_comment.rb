# -*- coding: utf-8 -*-
# 反射
# - "1" があると，"0" にして向きを反転する
# - "2" があると止る
def tt014(c)
  i = 1
  q = 1
  while q != 0 do
    if c[i] == 2 then
      q = 0
    else
      if c[i] == 0 then
        if q == 1 then
          i = i + 1
        else
          i = i - 1
        end
      else
        c[i] = 0
        if q == 1 then
          i = i - 1
          q = 2
        else
          i = i + 1
          q = 1
        end
      end
    end
    printf("%s %d, %s\n", q, i, c.to_s)
  end
  p c
end

tape = [2, 0, 0, 1, 0, 1, 2]
tt014(tape)
tt014(tape)
tt014(tape)
