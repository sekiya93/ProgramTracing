def r001(c)
  if c > 1 then
    return r001(c/2)
  else
    return c
  end
end
