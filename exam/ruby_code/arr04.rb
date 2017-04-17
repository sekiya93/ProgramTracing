def arr04(c, s)
  n = c.size
  for i in 0..s/2-1
    t        = c[i]
    c[i]     = c[s-1-i]
    c[s-1-i] = t
  end
  for s in 0..n/2-1
    t        = c[i]
    c[i]     = c[n-1-i]
    c[n-1-i] = t
  end
  for i in 0..n/2-1
    t = c[i]
    c[i] = c[n-1-i]
    c[n-1-i]=t
  end
  p c
end
