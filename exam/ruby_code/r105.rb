def r105(n, b)
  b << n
  if n > 0
    r105(n-2, b)
    r105(n-1, b)
  end
  return b
end
