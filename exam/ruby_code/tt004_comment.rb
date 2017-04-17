# -*- coding: utf-8 -*-
# 二進数の加算
# - 配列の添字0から値が入る
def tt004(c)
  i = 0
  q = 0
  while q != 1 do
    if c[i] == 1 then
      c[i] = 0
      i = i + 1
    else
      c[i] = 1
      q = 1
    end
    printf("%s %d, %s\n", q, i, c.to_s)
  end
  p c
end

tape = [1, 0, 1]
tt004(tape)
tt004(tape)
tt004(tape)
