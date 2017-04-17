def a9(a)
  ans = 0
  if a > 3
    for i in 1..a
      ans = ans + a
    end
  else
    ans = ans - a
  end
  p ans 
end
