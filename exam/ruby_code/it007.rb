def it007(a)
  i = 1
  s = 0
  while i <= a do
    if i % 2 == 0 then
      s = s + 3
    else
      s = s - 1
    end
    i = i + 1
  end
  p s
end
