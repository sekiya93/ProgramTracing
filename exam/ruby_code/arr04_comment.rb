# -*- coding: utf-8 -*-
# 入れ替え
# - 配列 c の先頭からs個を後ろに持って行く
# - sの個数によらず，反転を3回行うことで，後ろに移動する
# - ローテーション(arr01) を繰り返しても同じ操作は可能
def arr04(c, s)
  n = c.size
  for i in 0..s/2-1
    t        = c[i]
    c[i]     = c[s-1-i]
    c[s-1-i] = t
  end
  p c # 動作確認用の表示
  for i in 0..n/2-1
    t        = c[i]
    c[i]     = c[n-1-i]
    c[n-1-i] = t
  end
  p c # 動作確認用の表示
  for i in 0..(n - s)/2-1
    t          = c[i]
    c[i]       = c[n-s-1-i]
    c[n-s-1-i] = t
  end
  p c
end

# 動作確認
c = [1, 8, 6, 2, 3, 4]
p c 
arr04(c, 2)

