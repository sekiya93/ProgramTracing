def arr02(c)
  n = c.size
  for i in 1..n-1 do
    t        = c[n-i]
    c[n-i]   = c[n-i-1]
    c[n-i-1] = t
  end
  p c
end
