def arr08(c)
  n = c.size
  m = c[0]
  for i in (1..n-1) do
    if m > c[i] then
      m = c[i]
    end
  end
  p m
end
