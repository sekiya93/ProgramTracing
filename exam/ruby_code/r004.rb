def r004(i, a)
  if i == 0 then
    return a[0]
  else
    m = r004(i-1, a)
    if m > a[i] then
      return m
    else
      return a[i]
    end
  end
end
