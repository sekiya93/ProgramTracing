def it004(a)
  i = 1
  s = 0
  while i <= 5 do
    if i > 3 then
      s = s + a
    else
      s = s - 1
    end
    i = i + 1
  end
  p s
end
