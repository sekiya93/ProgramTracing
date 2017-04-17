def r104(n)
  p n
  if n > 0
    r104(n-2)
    r104(n-1)
  end
end
