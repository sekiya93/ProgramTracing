def b10(a)
  ans = 0
  if a == 3
    ans = ans + a
  else
    i = 1
    while i <= a do
      ans = ans - a
      i = i + 1
    end
  end
  p ans 
end
