# -*- coding: utf-8 -*-
# 反転
def tt013(c)
  i = 0
  q = 0
  while q != 1 do
    if c[i] == 1 then
      c[i] = 0
    else
      if c[i] == 0 then
        c[i] = 1
      else
        q = 1
      end
    end
    i = i + 1
    printf("%s %d, %s\n", q, i, c.to_s)
  end
  p c
end

tape = [1, 1, 1, 1, 0]
tt013(tape)
tt013(tape)
tt013(tape)
tt013(tape)
tt013(tape)
tt013(tape)
