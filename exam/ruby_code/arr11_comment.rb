def arr11(c)
  n = c.size
  for i in 0..n-1 do
    t    = c[i]
    c[i] = c[t]
    c[t] = t
  end
  p c
end

# c = [1, 3, 2, 4, 0]
# p c 
# arr11(c)
c = [1, 2, 3, 4, 0]
p c 
arr11(c)

