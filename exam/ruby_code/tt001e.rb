def tt001e(c)
  i = 1
  q = 1
  while q == 1 do
    if c[i] == 1 then
      c[i] = 2
      i = i + 1
    else
      if c[i] == 2 then
        c[i] = 0
        i = i - 1
      else
        q = 0
      end
    end
  end
  p c
end
