def it005(a)
  i = 0
  s = 0
  while s < a do
    if i % 2 == 0 then
      s = s + 2
    else
      s = s - 1
    end
    i = i + 1
  end
  p i
end
