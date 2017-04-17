def r106(n, b)
  b << n
  if n > 0
    r106(n-2,b)
    r106(n-1,b)
  end
  return b
end
