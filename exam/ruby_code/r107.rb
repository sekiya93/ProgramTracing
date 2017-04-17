def r107(n)
  if n < 1
    return [n]
  else
    return r107(n-2)+[n]+r107(n-1)
  end
end
