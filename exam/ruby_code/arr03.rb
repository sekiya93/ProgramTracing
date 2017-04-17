def arr03(c)
  n = c.size
  for i in 0..n/2-1
    t        = c[i]
    c[i]     = c[n-1-i]
    c[n-1-i] = t
  end
  p c
end
