def tt011(c)
  i = 0
  q = 0
  while q != 1 do
    if c[i] == 1 then
      c[i] = 2
    else
      if c[i] == 2 then
        c[i] = 1
      else
        q = 1
      end
    end
    i = i + 1
  end
  p c
end
