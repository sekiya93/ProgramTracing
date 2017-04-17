def tt009(c)
  i = 0
  q = 0
  while q < 6 do 
    if c[i] == 0 then
      if q == 0 then
        i = i + 1
        q = 0
      elsif q == 1 then
        i = i + 1
        q = 2
      elsif q == 2 then
        c[i] = 1
        i = i - 1
        q = 3
      elsif q == 3 then
        i = i - 1
        q = 4
      elsif q == 4 then
        c[i] = 1
        i = i + 1
        q = 5
      elsif q == 5 then
        q = 6
      end
    else
      if q == 0 then
        c[i] = 0
        i = i + 1
        q = 1
      elsif q == 1 then
        i = i + 1
        q = 1
      elsif q == 2 then
        i = i + 1
        q = 2
      elsif q == 3 then
        i = i - 1
        q = 3
      elsif q == 4 then
        i = i - 1
        q = 4
      elsif q == 5 then
        c[i] = 0
        i = i + 1
        q = 1
      end
    end
  end
  p c
end
