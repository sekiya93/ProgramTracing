def r005(i, a)
  if i == 0 then
    return a[0]
  else
    return r005(i-1, a) + a[i]
  end
end
  
