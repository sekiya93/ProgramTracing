def tt006(c)
  i = 0
  j = 1
  while j != 0 do
    if j == 2 then
      c[i] = 0
      j = 0
    else
      if c[i] == 1 then
        i = i + 1
      else
        i = i - 1
        j = 2
      end
    end
  end
  p c
end

