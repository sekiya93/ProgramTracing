def arr06(c, a)
  n = c.size
  k =  10000
  m = -10000
  for j in 1..a do
    for i in 0..n-1
      if c[i] > m && c[i] < k
        m = c[i]
      end
    end
    k = m 	
  end
  p m
end
