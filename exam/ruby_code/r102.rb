def r102(n)
  p n
  for i in 1..n-1
    r102(i)
  end
end
