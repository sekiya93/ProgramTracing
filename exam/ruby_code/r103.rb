def r103(n)
  s = n
  for i in 1..n-1
    s = s + r103(i)
  end
  return s
end
