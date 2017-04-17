def arr12(c)
  n = c.size

  bool = []
  for i in 0..n-1 do
    b[i]    = false
  end

  for i in 0..n-1 do
    b[c[i]] = true
  end

  count = 0
  for i in 0..n-1 do
    if b[i] then
      count = count + 1
    end
  end

  p count
end
  
