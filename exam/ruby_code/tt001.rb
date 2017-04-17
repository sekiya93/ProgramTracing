def tt001(a)
  c = [0,1,1,1,2,2]

  i = 1
  j = 1
  while j == 1 do
    if c[i] == 1 then
      c[i] = 2
      i = i+1
    else
      if c[i] == a then
        c[i] = 0
        i = i-1
      else
        j = 0
      end
    end
  end
  p i
end
