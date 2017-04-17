def arr09(c, limit)
  n = c.size
  i = 0
  sum = 0
  while (sum < limit && i < n) do
    sum = sum + c[i]
    i = i + 1
  end
  p i
end
    
