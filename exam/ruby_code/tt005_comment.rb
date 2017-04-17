# -*- coding: utf-8 -*-
# 単進数の加算
def tt005(c)
  i = 0
  q = 0
  while q != 1 do
    if c[i] == 1 then
      i = i + 1
    else
      c[i] = 1
      q = 1
    end
    printf("%s %d, %s\n", q, i, c.to_s)
  end
  p c
end

tape = [1, 1]
tt005(tape)
tt005(tape)
