def r003(n, k)
  if k > n then 
    return 0
  elsif k == 0 then
    return 1
  else
    return r003(n-1, k-1) + r003(n-1, k)
  end
end
