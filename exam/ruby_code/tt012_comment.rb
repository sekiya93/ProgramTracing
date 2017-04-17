# -*- coding: utf-8 -*-
# 単進数の減算
def tt012(c)
  i = 0
  q = 0
  while q != 3 do
    if c[i] == 1 then
      if q == 2 then
        # 削除した上で終了
        c[i] = 0
        q = 3
      else
        i = i + 1
        q = 1
      end
    else
      if q == 0 then
        # 終了
        q = 3
      else
        # 削除モードに移行
        i = i - 1
        q = 2
      end
    end
    printf("%s %d, %s\n", q, i, c.to_s)
  end
  p c
end

tape = [1, 1, 1, 1, 0]
tt012(tape)
tt012(tape)
tt012(tape)
tt012(tape)
tt012(tape)
tt012(tape)
