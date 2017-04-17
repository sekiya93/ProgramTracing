def arr11(c)
  n = c.size
  for i in 0..n-1 do
    t    = c[i]
    c[i] = c[t]
    c[t] = t
  end
  p c
end


