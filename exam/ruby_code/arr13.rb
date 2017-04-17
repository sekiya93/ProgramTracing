def arr13(c)
  count = 0
  n = c.size
  for i in 0..n-2 do
    for j in i+1..n-1 do
      if c[i] > c[j] then
        count = count + 1
      end
    end
  end
  p count
end
