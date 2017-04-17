def it001(a)
  i = 1
  s = 0
  while i <= 5 do
    if i < a then
      s = s + 1
    else
      s = s + 2
    end
    i = i + 1
  end
  p s
end
