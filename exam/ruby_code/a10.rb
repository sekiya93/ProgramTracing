def a10(a)
  ans = 0
  if a == 3
    ans = ans + a
  else
    for i in 1..a
      ans = ans - a
    end
  end
  p ans 
end
