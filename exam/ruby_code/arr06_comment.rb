# -*- coding: utf-8 -*-
def arr06(c, a)
  n = c.size
  k =  10000   # 配列 c のどの要素よりも大きな値

  for j in 1..a do
    m = -10000 # 配列 c のどの要素よりも小さな値
    for i in 0..n-1
      if c[i] > m && c[i] < k then
        m = c[i]
      end
    end
    k = m 	
  end

  p m
end

# 動作確認
c = [1, 8, 6, 2, 3, 4]
p c 
arr06(c, 1)
arr06(c, 3)



