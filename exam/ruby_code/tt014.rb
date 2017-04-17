def tt014(c)
  i = 2
  q = 1
  while q != 0 do
    if c[i] == 2 then
      q = 0
    else
      if c[i] == 0 then
        if q == 1 then
          i = i + 1
        else
          i = i - 1
        end
      else
        c[i] = 0
        if q == 1 then
          i = i - 1
          q = 2
        else
          i = i + 1
          q = 1
        end
      end
    end
  end
  p c
end
