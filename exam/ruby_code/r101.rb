def r101(n)
  if n < 1
    return 1
  else
    return r101(n-1) + n
  end
end
