def tt008(c)
  i = 0
  q = 0
  while q < 6 do 
    if c[i] == 0 then
      if q == 0 then
        i = i + 1
        q = 1
      elsif q == 1 then
        q = 6
      elsif q == 2 then
        i = i + 1
        q = 3
      elsif q == 3 then
        c[i] = 1
        i = i - 1
        q = 4
      elsif q == 4 then
        i = i - 1
        q = 5
      else
        # q == 5 
        c[i] = 1
        i = i + 1
        q = 1
      end
    else
      if q == 1 then
        c[i] = 0
        i = i + 1
        q = 2
      elsif q == 2 then
        i = i + 1
        q = 2
      elsif q == 3 then
        i = i + 1
        q = 3
      elsif q == 4 then
        i = i - 1
        q = 4
      else
        # q == 5 
        i = i - 1
        q = 5
      end
    end
    printf("(q, i, c) = (%d, %d, %s)\n", q, i, c.to_s)
  end
  p c
end

tt008([0, 1, 1, 1, 0, 0, 0, 0, 0, 0])
