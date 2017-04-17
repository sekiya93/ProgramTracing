def b9(a)
  ans = 0
  if a > 3
    i = 1
    while i <= a do
      ans = ans + a
      i = i + 1
    end
  else
    ans = ans - a
  end
  p ans 
end
