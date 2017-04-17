def tt005(c)
  i = 0
  q = 0
  while q != 1 do
    if c[i] == 1 then
      i = i + 1
    else
      c[i] = 1
      q = 1
    end
  end
  p c
end

