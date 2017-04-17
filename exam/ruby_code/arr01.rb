def arr01(c)
  n = c.size
  for i in 0..n-2
    t      = c[i]
    c[i]   = c[i+1]
    c[i+1] = t
  end
  p c
end
