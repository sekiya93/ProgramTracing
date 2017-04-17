def r002(c)
  if c > 1 then
    return c * r002(c-1)
  else
    return c
  end
end
